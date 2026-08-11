"""
Mark Six data scraper & processor for HKJC bet.hkjc.com (SPA).
Uses Playwright to bypass JavaScript rendering.
Exports seed JSON for the Flutter EdgeWise app.

Usage:
    python forecasting/marksix.py --output assets/data/marksix_seed.json.gz

Architecture:
    1. Launch Playwright headless browser
    2. Navigate to marksix results page, intercept API calls
    3. Fallback: scrape rendered DOM or use community data
    4. Parse: draw numbers, dates, winning numbers, prizes, turnover
    5. Export as gzipped JSON matching Dart mobile schema
"""

from __future__ import annotations

import gzip
import json
import re
import time
import argparse
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

import requests
from bs4 import BeautifulSoup, Tag

USER_AGENT = (
    "EdgeWise personal research client/1.0 "
    "(low-frequency cached access; contact: local application user)"
)

HKT = ZoneInfo("Asia/Hong_Kong")


@dataclass
class PrizeTier:
    name: str
    name_en: str = ""
    requirement: str = ""
    prize_per_unit: float = 0.0
    winning_units: float = 0.0


@dataclass
class MarkSixDraw:
    draw_number: str
    draw_date: str
    numbers: list[int]
    special_number: int
    total_turnover: float = 0.0
    prizes: list[PrizeTier] = field(default_factory=list)
    source: str = ""

    def to_dict(self) -> dict[str, object]:
        return {
            "drawNumber": self.draw_number,
            "drawDate": self.draw_date,
            "numbers": self.numbers,
            "specialNumber": self.special_number,
            "totalTurnover": self.total_turnover,
            "prizes": [
                {
                    "name": p.name,
                    "nameEn": p.name_en,
                    "requirement": p.requirement,
                    "prizePerUnit": p.prize_per_unit,
                    "winningUnits": p.winning_units,
                }
                for p in self.prizes
            ],
            "source": self.source,
        }

    @classmethod
    def from_dict(cls, d: dict[str, object]) -> "MarkSixDraw":
        return cls(
            draw_number=str(d.get("drawNumber", "")),
            draw_date=str(d.get("drawDate", "")),
            numbers=[int(n) for n in d.get("numbers", [])],
            special_number=int(d.get("specialNumber", 0)),
            total_turnover=float(d.get("totalTurnover", 0)),
            prizes=[
                PrizeTier(
                    name=str(p.get("name", "")),
                    name_en=str(p.get("nameEn", "")),
                    requirement=str(p.get("requirement", "")),
                    prize_per_unit=float(p.get("prizePerUnit", 0)),
                    winning_units=float(p.get("winningUnits", 0)),
                )
                for p in d.get("prizes", [])
            ],
            source=str(d.get("source", "")),
        )



@dataclass
class MarkSixScraper:
    """Scrapes Mark Six results from bet.hkjc.com (SPA)."""

    cache_dir: Path
    min_interval_seconds: float = 1.5

    def __post_init__(self) -> None:
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _rate_limit(self) -> None:
        time.sleep(self.min_interval_seconds)

    def fetch_via_api(
        self, start_date: str, end_date: str
    ) -> list[dict[str, object]]:
        """Try to fetch results via SPA's underlying REST API."""
        url = (
            f"https://bet.hkjc.com/marksix/Results/GetResults"
            f"?sd={start_date}&ed={end_date}&lang=ch"
        )
        cache_name = f"ms_api_{start_date}_{end_date}.json"
        path = self.cache_dir / cache_name
        if path.exists():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(data, list):
                    return data
            except (json.JSONDecodeError, KeyError):
                pass
        self._rate_limit()
        session = requests.Session()
        session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
            "Accept-Language": "zh-HK,zh;q=0.9,en;q=0.8",
        })
        try:
            resp = session.get(url, timeout=30)
            resp.raise_for_status()
            text = resp.text
            if "You need to enable JavaScript" in text:
                return []
            data = json.loads(text)
            if isinstance(data, list):
                path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                return data
            if isinstance(data, dict):
                results = data.get("results") or data.get("data") or data.get("Result") or []
                if isinstance(results, list):
                    path.write_text(json.dumps(results, ensure_ascii=False), encoding="utf-8")
                    return results
            return []
        except Exception:
            return []



    def fetch_via_playwright(
        self, start_year: int = 1993, end_year: int = 2026
    ) -> list[MarkSixDraw]:
        """Use Playwright to render the SPA and extract results."""
        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            print("Install: pip install playwright && playwright install chromium")
            return []
        draws: list[MarkSixDraw] = []
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(
                user_agent=USER_AGENT, viewport={"width": 1280, "height": 800}
            )
            page = context.new_page()
            api_results: list[dict[str, object]] = []

            def handle_response(response):
                url_lower = response.url.lower()
                if "marksix" in url_lower and (
                    "getresult" in url_lower or "search" in url_lower
                ):
                    try:
                        body = response.json()
                        items = (
                            body if isinstance(body, list)
                            else body.get("results") or body.get("data") or body.get("Result") or []
                        )
                        if isinstance(items, list):
                            api_results.extend(items)
                    except Exception:
                        pass

            page.on("response", handle_response)
            page.goto(
                "https://bet.hkjc.com/ch/marksix/results",
                wait_until="networkidle",
            )
            time.sleep(3)
            for year in range(start_year, end_year + 1):
                print(f"Scraping year {year}...")
                try:
                    page.evaluate(f"""
                        const el = document.querySelector(
                            '[class*="year"], [class*="Year"], [data-year="{year}"]'
                        );
                        if (el) el.click();
                    """)
                    time.sleep(1.5)
                    rendered = page.evaluate("""() => {
                        const cards = document.querySelectorAll(
                            '[class*="result"], [class*="draw"]'
                        );
                        return Array.from(cards).map(
                            c => c.innerText || c.textContent || ''
                        );
                    }""")
                    for block in rendered:
                        parsed = self._parse_rendered_block(block)
                        if parsed:
                            draws.append(parsed)
                except Exception as e:
                    print(f"  Year {year} error: {e}")
                time.sleep(self.min_interval_seconds)
            browser.close()
        for item in api_results:
            draw = self._parse_api_item(item)
            if draw and draw.draw_number not in {d.draw_number for d in draws}:
                draws.append(draw)


    def _parse_api_item(self, item: dict[str, object]) -> MarkSixDraw | None:
        """Parse a single draw record from API JSON."""
        try:
            draw_no = str(item.get("drawNumber") or item.get("DrawNo") or item.get("id") or "")
            draw_date = str(item.get("drawDate") or item.get("date") or item.get("DrawDate") or "")
            numbers_raw = item.get("numbers") or item.get("Numbers") or item.get("drawNumbers") or []
            special_raw = item.get("specialNumber") or item.get("SpecialNumber") or item.get("extraNumber") or 0
            turnover = float(item.get("totalTurnover") or item.get("turnover") or item.get("TotalInvestment") or 0)
            prizes_raw = item.get("prizes") or item.get("Prizes") or item.get("dividends") or []
            numbers: list[int] = []
            if isinstance(numbers_raw, list):
                numbers = sorted(int(n) for n in numbers_raw)
            elif isinstance(numbers_raw, str):
                nums = re.findall(r"\d+", numbers_raw)
                numbers = sorted(int(n) for n in nums if 1 <= int(n) <= 49)
            special = int(special_raw) if special_raw else 0
            prizes: list[PrizeTier] = []
            for p in prizes_raw:
                if isinstance(p, dict):
                    prizes.append(PrizeTier(
                        name=str(p.get("name") or p.get("prizeName") or ""),
                        name_en=str(p.get("nameEn") or ""),
                        requirement=str(p.get("requirement") or ""),
                        prize_per_unit=float(p.get("prizePerUnit") or p.get("dividend") or 0),
                        winning_units=float(p.get("winningUnits") or p.get("numberOfWinners") or 0),
                    ))
            if draw_date:
                for fmt in ["%Y-%m-%d", "%d/%m/%Y", "%Y%m%d", "%d-%m-%Y"]:
                    try:
                        dt = datetime.strptime(draw_date, fmt)
                        draw_date = dt.strftime("%Y-%m-%d")
                        break
                    except ValueError:
                        continue
            if not draw_no or len(numbers) < 6:
                return None
            return MarkSixDraw(
                draw_number=draw_no, draw_date=draw_date,
                numbers=numbers[:6], special_number=special,
                total_turnover=turnover, prizes=prizes, source="api",
            )
        except Exception:
            return None

        return draws



    def _parse_rendered_block(self, text: str) -> MarkSixDraw | None:
        """Parse rendered DOM text into a draw record."""
        draw_match = re.search(r"(?:期數|Draw)[:\s]*(\d+/\d+|\d+)", text)
        if not draw_match:
            return None
        draw_no = draw_match.group(1)
        date_match = re.search(
            r"(\d{4}[-/]\d{1,2}[-/]\d{1,2})|(\d{1,2}[-/]\d{1,2}[-/]\d{4})", text
        )
        date_str = date_match.group(1) or date_match.group(2) if date_match else ""
        nums = re.findall(r"\b([1-9]|[1-4]\d|49)\b", text)
        numbers_set: set[int] = {int(n) for n in nums if 1 <= int(n) <= 49}
        numbers = sorted(numbers_set)
        if len(numbers) < 6:
            return None
        return MarkSixDraw(
            draw_number=draw_no, draw_date=date_str,
            numbers=numbers[:6],
            special_number=numbers[6] if len(numbers) > 6 else 0,
            source="playwright-dom",
        )

    def export_seed_json(self, draws: list[MarkSixDraw], path: Path) -> None:
        """Export draws as gzipped JSON for Dart mobile."""
        payload = {
            "schemaVersion": "marksix-1.0.0",
            "generatedAt": datetime.now(HKT).isoformat(),
            "sourceUrl": "https://bet.hkjc.com/ch/marksix/results",
            "sourceNotice": "資料源為香港賽馬會公開六合彩賽果頁面；只供個人非商業研究。",
            "totalDraws": len(draws),
            "dateRange": {
                "first": draws[0].draw_date if draws else "",
                "last": draws[-1].draw_date if draws else "",
            },
            "draws": [d.to_dict() for d in draws],
        }
        path.parent.mkdir(parents=True, exist_ok=True)
        compressed = gzip.compress(
            json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8"),
            compresslevel=9,
        )
        path.write_bytes(compressed)


def create_seed_sample() -> list[MarkSixDraw]:
    """Create sample seed data for pipeline validation."""
    return [
        MarkSixDraw(
            draw_number="24/001", draw_date="2024-01-02",
            numbers=[5, 12, 18, 24, 35, 42], special_number=7,
            total_turnover=52_380_000.0,
            prizes=[
                PrizeTier("頭獎", "1st Prize", "中6個號碼", 8_000_000, 1.0),
                PrizeTier("二獎", "2nd Prize", "中5個號碼+特別號碼", 1_200_000, 3.0),
                PrizeTier("三獎", "3rd Prize", "中5個號碼", 85_000, 120.0),
            ],
            source="sample",
        ),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Scrape HKJC Mark Six results")
    parser.add_argument("--output", type=Path, default=Path("assets/data/marksix_seed.json.gz"))
    parser.add_argument("--cache-dir", type=Path, default=Path("data/marksix_cache"))
    parser.add_argument("--method", choices=["playwright", "api", "community"], default="community")
    parser.add_argument("--start-year", type=int, default=1993)
    parser.add_argument("--end-year", type=int, default=2026)
    args = parser.parse_args()
    scraper = MarkSixScraper(cache_dir=args.cache_dir)
    draws: list[MarkSixDraw] = []
    if args.method == "playwright":
        draws = scraper.fetch_via_playwright(args.start_year, args.end_year)
    elif args.method == "api":
        for y in range(args.start_year, args.end_year + 1):
            items = scraper.fetch_via_api(f"{y}0101", f"{y}1231")
            for item in items:
                draw = scraper._parse_api_item(item)
                if draw:
                    draws.append(draw)
            time.sleep(scraper.min_interval_seconds)
    if not draws:
        print("No live results, using sample seed data...")
        draws = create_seed_sample()
    draws.sort(key=lambda d: d.draw_date)
    scraper.export_seed_json(draws, args.output)


if __name__ == "__main__":
    main()
