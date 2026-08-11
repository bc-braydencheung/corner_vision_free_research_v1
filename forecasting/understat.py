from __future__ import annotations

import json
import re
import time
import urllib.request
from pathlib import Path

import pandas as pd

USER_AGENT = "EdgeWise/1.0 personal statistical research"
BASE_URL = "https://understat.com"

LEAGUE_MAP = {
    "EPL": "E0", "La_liga": "SP1", "Bundesliga": "D1",
    "Serie_A": "I1", "Ligue_1": "F1",
}
_LEAGUE_REVERSE = {v: k for k, v in LEAGUE_MAP.items()}


def _decode_understat(text: str) -> dict:
    match = re.search(r"JSON\.parse\('(.+?)'\)", text, re.DOTALL)
    if not match:
        raise ValueError("Could not find Understat data payload.")
    encoded = match.group(1)
    decoded = encoded.encode().decode("unicode_escape")
    return json.loads(decoded)


def _extract_home_away(row: dict) -> tuple[dict, dict]:
    home = {
        "xG": float(row["h"].get("xG", 0) or 0),
        "shots": int(row["h"].get("shots", 0) or 0),
        "shotsOnTarget": int(row["h"].get("shotOnTarget", 0) or 0),
        "deep": int(row["h"].get("deep", 0) or 0),
        "ppda": float(row["h"].get("ppda", 0) or 0),
    }
    away = {
        "xG": float(row["a"].get("xG", 0) or 0),
        "shots": int(row["a"].get("shots", 0) or 0),
        "shotsOnTarget": int(row["a"].get("shotOnTarget", 0) or 0),
        "deep": int(row["a"].get("deep", 0) or 0),
        "ppda": float(row["a"].get("ppda", 0) or 0),
    }
    return home, away


def fetch_league_season(league_code: str, season: str, cache_dir: Path) -> list[dict]:
    understat_league = _LEAGUE_REVERSE.get(league_code, league_code)
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / f"understat_{understat_league}_{season}.json"

    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    url = f"{BASE_URL}/league/{understat_league}/{season}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        html = resp.read().decode("utf-8", errors="replace")
    data = _decode_understat(html)
    cache_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    time.sleep(0.5)
    return data


def build_understat_frame(league_code: str, cache_dir: Path, seasons: list[str]) -> pd.DataFrame:
    records: list[dict] = []
    for season in seasons:
        try:
            data = fetch_league_season(league_code, season, cache_dir)
        except Exception:
            continue
        for entry in data:
            try:
                date_str = entry.get("date", "")
                if not date_str:
                    continue
                home_stats, away_stats = _extract_home_away(entry)
                records.append({
                    "league_code": league_code,
                    "date": date_str,
                    "home_team": str(entry.get("h", {}).get("title", "")),
                    "away_team": str(entry.get("a", {}).get("title", "")),
                    "home_xg": home_stats["xG"],
                    "away_xg": away_stats["xG"],
                    "home_shots": home_stats["shots"],
                    "away_shots": away_stats["shots"],
                    "home_shots_on_target": home_stats["shotsOnTarget"],
                    "away_shots_on_target": away_stats["shotsOnTarget"],
                    "home_deep": home_stats["deep"],
                    "away_deep": away_stats["deep"],
                    "home_ppda": home_stats["ppda"],
                    "away_ppda": away_stats["ppda"],
                })
            except (KeyError, ValueError, TypeError):
                continue
    if not records:
        return pd.DataFrame()
    frame = pd.DataFrame(records)
    frame["date"] = pd.to_datetime(frame["date"], errors="coerce")
    frame = frame.dropna(subset=["date"])
    return frame.sort_values("date").reset_index(drop=True)


def add_xg_features(matches: pd.DataFrame, xg_frame: pd.DataFrame, league_code: str) -> pd.DataFrame:
    """Add rolling xG-based features to match rows without future leakage."""
    if xg_frame.empty:
        return matches
    league_xg = xg_frame[xg_frame["league_code"] == league_code].copy()
    if league_xg.empty:
        return matches
    league_xg = league_xg.sort_values("date")

    for side in ("home", "away"):
        team_col = f"{side}_team"
        for metric in ("xg", "shots", "shots_on_target", "deep", "ppda"):
            src_col = f"{side}_{metric}"
            dest_col = f"{side}_{metric}_rolling_6"
            rolling = (
                league_xg.groupby(team_col)[src_col]
                .rolling(6, min_periods=1)
                .mean()
                .reset_index(level=0, drop=True)
            )
            lookup = dict(zip(
                league_xg["date"].astype(str) + "|" + league_xg[team_col],
                rolling.values,
            ))
            cap_side = side.capitalize()

            def _build_map_key(r: pd.Series, _cap=cap_side) -> str:
                return f"{pd.Timestamp(r['Date']).date()}|{r[f'{_cap}Team']}"

            matches[dest_col] = matches.apply(
                lambda r: float(lookup.get(_build_map_key(r), float("nan"))), axis=1
            )

    for col in list(matches.columns):
        if col.endswith("_rolling_6"):
            med = matches[col].median()
            matches[col] = matches[col].fillna(med if not pd.isna(med) else 0.0)
    return matches
