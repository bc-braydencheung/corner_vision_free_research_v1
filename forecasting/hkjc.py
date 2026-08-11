from __future__ import annotations

import json
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import pandas as pd
import requests
from bs4 import BeautifulSoup, Tag

BASE_URL = "https://racing.hkjc.com/en-us/local/information"
CHINESE_BASE_URL = "https://racing.hkjc.com/zh-hk/local/information"
USER_AGENT = (
    "EdgeWise personal research client/1.0 "
    "(low-frequency cached access; contact: local application user)"
)


def _number(value: str) -> float | None:
    cleaned = value.replace(",", "").replace("+", "").strip()
    if not cleaned or cleaned == "-":
        return None
    try:
        return float(cleaned)
    except ValueError:
        return None


def _venue_code(venue: str) -> str:
    return "HV" if "VALLEY" in venue.upper() else "ST"


def _horse_id(cell: Tag, horse_name: str) -> str:
    link = cell.find("a", href=True)
    if link:
        match = re.search(r"horseid=([^&]+)", link["href"], re.IGNORECASE)
        if match:
            return match.group(1).replace("HK_", "")
    match = re.search(r"\(([A-Z]\d{3})\)", horse_name)
    return match.group(1) if match else horse_name.upper().replace(" ", "_")


def _race_metadata(text: str) -> dict[str, object]:
    distance_match = re.search(r"(\d{3,4})M", text, re.IGNORECASE)
    class_match = re.search(r"\bClass\s+([A-Za-z0-9]+)", text, re.IGNORECASE)
    surface = "AWT" if "ALL WEATHER" in text.upper() else "TURF"
    course_match = re.search(
        r'(?:TURF|ALL WEATHER TRACK)\s*(?:-|,)\s*'
        r'("[A-Z+0-9]+"\s+Course|[^-\n]+?Course)',
        text,
        re.IGNORECASE,
    )
    going_match = re.search(
        r"\b(GOOD TO FIRM|GOOD TO YIELDING|WET SLOW|WET FAST|YIELDING|"
        r"GOOD|SOFT|FAST|SLOW)\b",
        text,
        re.IGNORECASE,
    )
    return {
        "distance": int(distance_match.group(1)) if distance_match else 0,
        "race_class": class_match.group(1) if class_match else "Open",
        "surface": surface,
        "course": course_match.group(1).strip() if course_match else "",
        "going": going_match.group(1).upper() if going_match else "",
    }


def parse_results_all(html: str, race_date: date) -> list[dict[str, object]]:
    soup = BeautifulSoup(html, "html.parser")
    venue_table = soup.find("table", class_="js_racecard")
    venue = (
        venue_table.get_text(" ", strip=True).split(":")[0]
        if venue_table is not None
        else ""
    )
    if not venue:
        return []
    venue_code = _venue_code(venue)
    records: list[dict[str, object]] = []
    race_blocks = soup.select("div.race_result > div.f_fs13.margin_top15")
    for block in race_blocks:
        race_label = block.find("div", class_="bg_blue")
        result_table = block.find("table", class_="result")
        if race_label is None or result_table is None:
            continue
        number_match = re.search(r"(\d+)", race_label.get_text(" ", strip=True))
        if number_match is None:
            continue
        race_number = int(number_match.group(1))
        metadata_node = race_label.find_next_sibling("div")
        metadata_text = (
            metadata_node.get_text(" ", strip=True) if metadata_node else ""
        )
        metadata = _race_metadata(metadata_text)
        rows = result_table.find_all("tr")
        runner_rows: list[tuple[list[Tag], int]] = []
        for row in rows[1:]:
            cells = row.find_all("td")
            if len(cells) < 7:
                continue
            position_match = re.match(r"\d+", cells[0].get_text(" ", strip=True))
            if position_match is None:
                continue
            runner_rows.append((cells, int(position_match.group())))
        field_size = len(runner_rows)
        if field_size < 2:
            continue
        place_slots = 3 if field_size >= 7 else 2 if field_size >= 4 else 0
        race_id = f"HK:{race_date.isoformat()}:{venue_code}:{race_number}"
        for cells, finish_position in runner_rows:
            horse_text = cells[2].get_text(" ", strip=True)
            horse_name = re.sub(r"\s*\([A-Z]\d{3}\)\s*$", "", horse_text).strip()
            records.append(
                {
                    "race_id": race_id,
                    "date": race_date.isoformat(),
                    "venue": venue,
                    "venue_code": venue_code,
                    "race_number": race_number,
                    **metadata,
                    "horse_id": _horse_id(cells[2], horse_text),
                    "horse_name": horse_name,
                    "jockey": cells[3].get_text(" ", strip=True),
                    "trainer": cells[4].get_text(" ", strip=True),
                    "weight": _number(cells[5].get_text(" ", strip=True)),
                    "draw": _number(cells[6].get_text(" ", strip=True)),
                    "finish_position": finish_position,
                    "field_size": field_size,
                    "won": int(finish_position == 1),
                    "placed": int(finish_position <= place_slots),
                }
            )
    return records


def race_numbers_from_results_all(html: str) -> list[int]:
    soup = BeautifulSoup(html, "html.parser")
    values: list[int] = []
    for block in soup.select("div.race_result > div.f_fs13.margin_top15"):
        label = block.find("div", class_="bg_blue")
        if label is None:
            continue
        match = re.search(r"(\d+)", label.get_text(" ", strip=True))
        if match:
            values.append(int(match.group(1)))
    return values


def parse_local_result(html: str, race_date: date) -> list[dict[str, object]]:
    soup = BeautifulSoup(html, "html.parser")
    venue_table = soup.find("table", class_="js_racecard")
    venue = (
        venue_table.get_text(" ", strip=True).split(":")[0]
        if venue_table is not None
        else ""
    )
    tables = soup.find_all("table")
    metadata_table = next(
        (
            table
            for table in tables
            if re.search(r"RACE\s+\d+", table.get_text(" ", strip=True))
            and "Going" in table.get_text(" ", strip=True)
        ),
        None,
    )
    result_table = next(
        (
            table
            for table in tables
            if "Horse No." in table.get_text(" ", strip=True)
            and "Finish Time" in table.get_text(" ", strip=True)
        ),
        None,
    )
    if not venue or metadata_table is None or result_table is None:
        return []
    metadata_text = metadata_table.get_text(" ", strip=True)
    race_match = re.search(r"RACE\s+(\d+)", metadata_text)
    if race_match is None:
        return []
    race_number = int(race_match.group(1))
    metadata = _race_metadata(metadata_text)
    race_name_match = re.search(
        r"Going\s*:\s*(?:GOOD TO FIRM|GOOD TO YIELDING|WET SLOW|WET FAST|"
        r"YIELDING|GOOD|SOFT|FAST|SLOW)\s+(.*?)\s+Course\s*:",
        metadata_text,
        re.IGNORECASE,
    )
    venue_code = _venue_code(venue)
    runner_rows: list[tuple[list[Tag], int]] = []
    for row in result_table.find_all("tr")[1:]:
        cells = row.find_all("td")
        if len(cells) < 12:
            continue
        position_match = re.match(r"\d+", cells[0].get_text(" ", strip=True))
        if position_match is None:
            continue
        runner_rows.append((cells, int(position_match.group())))
    field_size = len(runner_rows)
    if field_size < 2:
        return []
    place_slots = 3 if field_size >= 7 else 2 if field_size >= 4 else 0
    race_id = f"HK:{race_date.isoformat()}:{venue_code}:{race_number}"
    records: list[dict[str, object]] = []
    for cells, finish_position in runner_rows:
        horse_text = cells[2].get_text(" ", strip=True)
        horse_name = re.sub(r"\s*\([A-Z]\d{3}\)\s*$", "", horse_text).strip()
        records.append(
            {
                "race_id": race_id,
                "date": race_date.isoformat(),
                "venue": venue,
                "venue_code": venue_code,
                "race_number": race_number,
                "race_name": (
                    race_name_match.group(1).strip() if race_name_match else ""
                ),
                **metadata,
                "horse_id": _horse_id(cells[2], horse_text),
                "horse_name": horse_name,
                "jockey": cells[3].get_text(" ", strip=True),
                "trainer": cells[4].get_text(" ", strip=True),
                "weight": _number(cells[5].get_text(" ", strip=True)),
                "horse_weight": _number(cells[6].get_text(" ", strip=True)),
                "draw": _number(cells[7].get_text(" ", strip=True)),
                "finish_position": finish_position,
                "field_size": field_size,
                "won": int(finish_position == 1),
                "placed": int(finish_position <= place_slots),
                "finish_time": cells[10].get_text(" ", strip=True),
                "win_odds": _number(cells[11].get_text(" ", strip=True)),
            }
        )
    return records


def parse_race_card(html: str) -> dict[str, object] | None:
    soup = BeautifulSoup(html, "html.parser")
    starter = soup.find("table", class_="starter")
    if starter is None:
        return None
    metadata_node = next(
        (
            node
            for node in soup.find_all("div", class_="f_fs13")
            if node.get_text(" ", strip=True).startswith("Race ")
        ),
        None,
    )
    if metadata_node is None:
        return None
    metadata_text = metadata_node.get_text(" ", strip=True)
    race_match = re.search(r"Race\s+(\d+)\s*-\s*(.*?)\s+(?:Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),", metadata_text)
    date_match = re.search(
        r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},\s+\d{4}",
        metadata_text,
    )
    venue_match = re.search(r",\s*(Sha Tin|Happy Valley),\s*\d{1,2}:\d{2}", metadata_text)
    time_match = re.search(r"(?:Sha Tin|Happy Valley),\s*(\d{1,2}:\d{2})", metadata_text)
    if (
        race_match is None
        or date_match is None
        or venue_match is None
        or time_match is None
    ):
        return None
    race_date = datetime.strptime(date_match.group(), "%B %d, %Y").date()
    start_time = datetime.combine(
        race_date,
        datetime.strptime(time_match.group(1), "%H:%M").time(),
        tzinfo=ZoneInfo("Asia/Hong_Kong"),
    )
    venue = venue_match.group(1)
    venue_code = _venue_code(venue)
    race_number = int(race_match.group(1))
    race_id = f"HK:{race_date.isoformat()}:{venue_code}:{race_number}"
    metadata = _race_metadata(metadata_text)
    runners: list[dict[str, object]] = []
    for row in starter.find_all("tr")[1:]:
        cells = row.find_all("td")
        if len(cells) < 27:
            continue
        horse_name = cells[3].get_text(" ", strip=True)
        if not horse_name:
            continue
        runners.append(
            {
                "horse_id": _horse_id(cells[3], horse_name),
                "horse_name": horse_name,
                "number": int(_number(cells[0].get_text(" ", strip=True)) or 0),
                "last_six": cells[1].get_text(" ", strip=True),
                "weight": _number(cells[5].get_text(" ", strip=True)),
                "jockey": cells[6].get_text(" ", strip=True),
                "draw": _number(cells[8].get_text(" ", strip=True)),
                "trainer": cells[9].get_text(" ", strip=True),
                "rating": _number(cells[11].get_text(" ", strip=True)),
                "rating_change": _number(cells[12].get_text(" ", strip=True)),
                "horse_weight": _number(cells[13].get_text(" ", strip=True)),
                "age": _number(cells[16].get_text(" ", strip=True)),
                "days_since_last_run": _number(cells[21].get_text(" ", strip=True)),
                "gear": cells[22].get_text(" ", strip=True),
            }
        )
    if len(runners) < 2:
        return None
    return {
        "race_id": race_id,
        "date": race_date.isoformat(),
        "start_time": start_time.isoformat(),
        "venue": venue,
        "venue_code": venue_code,
        "race_number": race_number,
        "race_name": race_match.group(2).strip(),
        **metadata,
        "runners": runners,
    }


def merge_bilingual_race_card(
    english: dict[str, object],
    chinese: dict[str, object] | dict[str, str] | None,
) -> dict[str, object]:
    chinese_names = (
        {
            str(runner["horse_id"]): str(runner["horse_name"])
            for runner in chinese.get("runners", [])
        }
        if chinese and "runners" in chinese
        else dict(chinese or {})
    )
    runners = []
    for raw in english["runners"]:
        runner = dict(raw)
        runner["horse_name_english"] = str(runner["horse_name"])
        runner["horse_name_chinese"] = chinese_names.get(
            str(runner["horse_id"]),
            "",
        )
        runners.append(runner)
    return {**english, "runners": runners}


def parse_race_card_names(html: str) -> dict[str, str]:
    soup = BeautifulSoup(html, "html.parser")
    starter = soup.find("table", class_="starter")
    if starter is None:
        return {}
    names: dict[str, str] = {}
    for row in starter.find_all("tr")[1:]:
        cells = row.find_all("td")
        if len(cells) < 4:
            continue
        horse_name = cells[3].get_text(" ", strip=True)
        if horse_name:
            names[_horse_id(cells[3], horse_name)] = horse_name
    return names


@dataclass
class HKJCScraper:
    cache_dir: Path
    min_interval_seconds: float = 0.75
    max_workers: int = 1

    def __post_init__(self) -> None:
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self._last_request = 0.0
        self._request_lock = threading.Lock()
        self._session_lock = threading.Lock()
        self._sessions: dict[int, requests.Session] = {}

    def _get(self, url: str, cache_name: str, refresh: bool = False) -> str:
        path = self.cache_dir / cache_name
        if path.exists() and not refresh:
            return path.read_text(encoding="utf-8")
        with self._request_lock:
            wait = self.min_interval_seconds - (
                time.monotonic() - self._last_request
            )
            if wait > 0:
                time.sleep(wait)
            self._last_request = time.monotonic()
        thread_id = threading.get_ident()
        with self._session_lock:
            if thread_id not in self._sessions:
                session = requests.Session()
                session.headers.update({"User-Agent": USER_AGENT})
                self._sessions[thread_id] = session
            session = self._sessions[thread_id]
        response = session.get(url, timeout=30)
        response.raise_for_status()
        path.write_text(response.text, encoding="utf-8")
        return response.text

    def discover_dates(self) -> set[date]:
        html = self._get(f"{BASE_URL}/localresults", "meeting-index.html", refresh=True)
        soup = BeautifulSoup(html, "html.parser")
        dates: set[date] = set()
        for option in soup.find_all("option"):
            text = option.get_text(" ", strip=True)
            try:
                dates.add(datetime.strptime(text, "%d/%m/%Y").date())
            except ValueError:
                continue
        return dates

    def candidate_dates(self, start: date, end: date) -> list[date]:
        discovered = {value for value in self.discover_dates() if start <= value <= end}
        current = start
        while current <= end:
            discovered.add(current)
            current += timedelta(days=1)
        return sorted(discovered)

    def sync_history(
        self,
        output: Path,
        start: date,
        end: date,
        max_requests: int | None = None,
    ) -> pd.DataFrame:
        output.parent.mkdir(parents=True, exist_ok=True)
        processed_path = output.with_suffix(".processed.json")
        processed = (
            set(json.loads(processed_path.read_text(encoding="utf-8")))
            if processed_path.exists()
            else set()
        )
        existing = pd.read_csv(output) if output.exists() else pd.DataFrame()
        if not existing.empty and "source_url" not in existing:
            def cached_retrieval(row: pd.Series) -> str:
                cache_path = self.cache_dir / (
                    f"local-{row['date']}-{int(row['race_number'])}.html"
                )
                timestamp = (
                    cache_path.stat().st_mtime
                    if cache_path.exists()
                    else output.stat().st_mtime
                )
                return datetime.fromtimestamp(timestamp).astimezone().isoformat()

            existing["source_url"] = existing.apply(
                lambda row: (
                    f"{BASE_URL}/localresults?RaceDate="
                    f"{str(row['date']).replace('-', '/')}&RaceNo={int(row['race_number'])}"
                ),
                axis=1,
            )
            existing["retrieved_at"] = existing.apply(cached_retrieval, axis=1)
            existing.to_csv(output, index=False)
        if existing.empty:
            processed.clear()
        new_records: list[dict[str, object]] = []
        requests_made = 0
        for meeting_date in self.candidate_dates(start, end):
            key = meeting_date.isoformat()
            if key in processed:
                continue
            if max_requests is not None and requests_made >= max_requests:
                break
            url = f"{BASE_URL}/resultsall?RaceDate={meeting_date:%Y/%m/%d}"
            try:
                html = self._get(url, f"results-{meeting_date.isoformat()}.html")
                requests_made += 1
                race_numbers = race_numbers_from_results_all(html)
                meeting_records: list[dict[str, object]] = []
                complete = True

                def load_race(
                    race_number: int,
                ) -> tuple[str, str, list[dict[str, object]]]:
                    race_url = (
                        f"{BASE_URL}/localresults?RaceDate={meeting_date:%Y/%m/%d}"
                        f"&RaceNo={race_number}"
                    )
                    race_html = self._get(
                        race_url,
                        f"local-{meeting_date.isoformat()}-{race_number}.html",
                    )
                    return (
                        race_url,
                        race_html,
                        parse_local_result(race_html, meeting_date),
                    )

                available_races = race_numbers
                if max_requests is not None:
                    available_races = race_numbers[
                        : max(0, max_requests - requests_made)
                    ]
                    if len(available_races) < len(race_numbers):
                        complete = False
                with ThreadPoolExecutor(
                    max_workers=max(1, self.max_workers)
                ) as executor:
                    race_results = list(executor.map(load_race, available_races))
                requests_made += len(available_races)
                for race_url, race_html, race_records in race_results:
                    if max_requests is not None and requests_made >= max_requests:
                        complete = len(available_races) == len(race_numbers)
                    if not race_records:
                        if "abandon" in race_html.lower():
                            continue
                        complete = False
                        break
                    retrieved_at = datetime.now().astimezone().isoformat()
                    for record in race_records:
                        record["source_url"] = race_url
                        record["retrieved_at"] = retrieved_at
                    meeting_records.extend(race_records)
            except requests.RequestException:
                continue
            if not race_numbers:
                complete = True
            if not complete:
                break
            new_records.extend(meeting_records)
            if meeting_records:
                existing = pd.concat(
                    [existing, pd.DataFrame(meeting_records)],
                    ignore_index=True,
                )
                existing = existing.drop_duplicates(
                    ["race_id", "horse_id"],
                    keep="last",
                )
                existing = existing.sort_values(
                    ["date", "race_number", "finish_position"]
                )
                existing.to_csv(output, index=False)
                new_records.clear()
            processed.add(key)
            processed_path.write_text(
                json.dumps(sorted(processed), ensure_ascii=False),
                encoding="utf-8",
            )
        frames = [
            frame for frame in (existing, pd.DataFrame(new_records)) if not frame.empty
        ]
        history = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()
        if not history.empty:
            history = history.drop_duplicates(["race_id", "horse_id"], keep="last")
            history = history.sort_values(["date", "race_number", "finish_position"])
            history.to_csv(output, index=False)
        return history

    def upcoming_races(self) -> list[dict[str, object]]:
        first_html = self._get(
            f"{BASE_URL}/racecard",
            f"racecard-current-{date.today().isoformat()}-1.html",
            refresh=True,
        )
        first = parse_race_card(first_html)
        if first is None:
            return []
        chinese_first_html = self._get(
            f"{CHINESE_BASE_URL}/racecard",
            f"racecard-current-{date.today().isoformat()}-1-zh.html",
            refresh=True,
        )
        first = merge_bilingual_race_card(
            first,
            parse_race_card_names(chinese_first_html),
        )
        soup = BeautifulSoup(first_html, "html.parser")
        race_numbers = {
            int(match.group(1))
            for link in soup.find_all("a", href=True)
            if (match := re.search(r"RaceNo=(\d+)", link["href"], re.IGNORECASE))
        }
        race_numbers.add(int(first["race_number"]))
        races = [first]
        race_date = datetime.fromisoformat(str(first["date"])).date()
        venue_code = str(first["venue_code"])
        for race_number in sorted(race_numbers):
            if race_number == int(first["race_number"]):
                continue
            url = (
                f"{BASE_URL}/racecard?RaceDate={race_date:%Y/%m/%d}"
                f"&Racecourse={venue_code}&RaceNo={race_number}"
            )
            try:
                html = self._get(
                    url,
                    f"racecard-{race_date.isoformat()}-{venue_code}-{race_number}.html",
                    refresh=True,
                )
                chinese_html = self._get(
                    (
                        f"{CHINESE_BASE_URL}/racecard?"
                        f"RaceDate={race_date:%Y/%m/%d}"
                        f"&Racecourse={venue_code}&RaceNo={race_number}"
                    ),
                    (
                        f"racecard-{race_date.isoformat()}-"
                        f"{venue_code}-{race_number}-zh.html"
                    ),
                    refresh=True,
                )
            except requests.RequestException:
                continue
            parsed = parse_race_card(html)
            if parsed is not None:
                races.append(
                    merge_bilingual_race_card(
                        parsed,
                        parse_race_card_names(chinese_html),
                    )
                )
        return sorted(races, key=lambda race: int(race["race_number"]))


def result_records(history: pd.DataFrame, days: int = 21) -> list[dict[str, object]]:
    if history.empty:
        return []
    dated = history.copy()
    dated["date"] = pd.to_datetime(dated["date"])
    cutoff = dated["date"].max() - pd.Timedelta(days=days)
    recent = dated.loc[dated["date"] >= cutoff]
    return [
        {
            "raceId": str(row.race_id),
            "horseId": str(row.horse_id),
            "finishPosition": int(row.finish_position),
        }
        for row in recent.itertuples()
    ]
