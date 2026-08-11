from __future__ import annotations

import re
import time
from dataclasses import dataclass
from datetime import date
from pathlib import Path

import pandas as pd
import requests
from bs4 import BeautifulSoup

USER_AGENT = (
    "EdgeWise personal research client/1.0 "
    "(low-frequency cached access; contact: local application user)"
)
TRIALS_RESULT_URL = (
    "https://racing.hkjc.com/en-us/local/information/barrier-trial-result"
)


@dataclass(frozen=True)
class TrialResult:
    horse_id: str
    horse_name: str
    trial_date: date
    venue: str
    distance: int
    going: str
    position: int
    time_secs: float | None


def _parse_trial_date(text: str) -> date | None:
    m = re.search(r"(\d{2})/(\d{2})/(\d{4})", text)
    if m:
        return date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", text)
    if m:
        return date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    return None


def _parse_trial_time(text: str) -> float | None:
    m = re.search(r"(\d{1,2})[.:](\d{2})[.:](\d{2})", text)
    if m:
        return float(m.group(1)) * 60 + float(m.group(2)) + float(m.group(3)) / 100
    m = re.search(r"(\d+\.?\d*)", text)
    if m:
        val = float(m.group(1))
        return val if val < 300 else None
    return None


def fetch_trial_results(
    cache_dir: Path, target_date: date | None = None, min_interval_seconds: float = 0.75,
) -> list[dict]:
    cache_dir.mkdir(parents=True, exist_ok=True)
    today = target_date or date.today()
    cache_path = cache_dir / f"trials_{today.isoformat()}.csv"
    if cache_path.exists():
        return pd.read_csv(cache_path).to_dict("records")

    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    records: list[dict] = []

    try:
        resp = session.get(TRIALS_RESULT_URL, timeout=30)
        resp.raise_for_status()
        time.sleep(min_interval_seconds)
    except Exception:
        return records

    soup = BeautifulSoup(resp.text, "html.parser")
    tables = soup.select("table.bd_tdb_font, table.js_racecard, table.result")

    for table in tables:
        date_header = table.find_previous("div", class_="bg_blue")
        trial_date = (
            _parse_trial_date(date_header.get_text(" ", strip=True))
            if date_header else None
        )
        if trial_date is None:
            continue

        cur_venue = ""
        cur_distance = 0
        cur_going = ""
        rows = table.find_all("tr")

        for row in rows:
            cells = row.find_all("td")
            if not cells:
                continue
            text = row.get_text(" ", strip=True)

            vm = re.search(r"(Sha Tin|Happy Valley|Conghua)", text, re.IGNORECASE)
            if vm:
                v = vm.group(1)
                cur_venue = "ST" if "Sha Tin" in v else "HV" if "Happy Valley" in v else "CH"
            dm = re.search(r"(\d{3,4})M", text, re.IGNORECASE)
            if dm:
                cur_distance = int(dm.group(1))
            gm = re.search(r"\b(GOOD|YIELDING|SOFT|FAST|SLOW|WET)\b", text, re.IGNORECASE)
            if gm:
                cur_going = gm.group(1).upper()

            if len(cells) < 4:
                continue
            pos_text = cells[0].get_text(" ", strip=True)
            pm = re.match(r"(\d+)", pos_text)
            if not pm:
                continue

            position = int(pm.group(1))
            horse_link = cells[1].find("a", href=True) if len(cells) > 1 else None
            horse_id = ""
            horse_name = cells[1].get_text(" ", strip=True) if len(cells) > 1 else ""
            if horse_link and "horseid=" in horse_link["href"]:
                hm = re.search(r"horseid=([^&]+)", horse_link["href"], re.IGNORECASE)
                horse_id = hm.group(1).replace("HK_", "") if hm else ""

            time_text = cells[3].get_text(" ", strip=True) if len(cells) > 3 else ""
            trial_time = _parse_trial_time(time_text)

            records.append({
                "horse_id": horse_id or horse_name.upper().replace(" ", "_"),
                "horse_name": horse_name,
                "trial_date": trial_date.isoformat(),
                "venue": cur_venue,
                "distance": cur_distance,
                "going": cur_going,
                "position": position,
                "time_secs": trial_time,
            })

    if records:
        pd.DataFrame(records).to_csv(cache_path, index=False)
    return records


def build_trial_features(history: pd.DataFrame, trial_cache_dir: Path) -> pd.DataFrame:
    """Add barrier trial features to racing history DataFrame (no leakage)."""
    trials = fetch_trial_results(trial_cache_dir)
    if not trials:
        return history

    trial_frame = pd.DataFrame(trials)
    trial_frame["trial_date"] = pd.to_datetime(trial_frame["trial_date"], errors="coerce")
    trial_frame = trial_frame.dropna(subset=["trial_date"])
    history = history.copy()
    history["date"] = pd.to_datetime(history["date"], errors="coerce")

    counts, avg_pos, best_time = [], [], []
    for _, race_row in history.iterrows():
        hid = str(race_row.get("horse_id", ""))
        rd = race_row["date"]
        ht = trial_frame[
            (trial_frame["horse_id"] == hid)
            & (trial_frame["trial_date"] < rd)
            & (trial_frame["trial_date"] >= rd - pd.Timedelta(days=120))
        ]
        counts.append(len(ht))
        avg_pos.append(ht["position"].mean() if not ht.empty else float("nan"))
        best_time.append(ht["time_secs"].min() if not ht.empty else float("nan"))

    history["trial_count_120d"] = counts
    history["trial_avg_position_120d"] = avg_pos
    history["trial_best_time_120d"] = best_time
    for col in ("trial_avg_position_120d", "trial_best_time_120d"):
        history[col] = history[col].fillna(0)
    return history
