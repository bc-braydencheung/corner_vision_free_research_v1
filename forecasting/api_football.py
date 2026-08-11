from __future__ import annotations

import json
import time
import urllib.request
from pathlib import Path

import pandas as pd

API_URL = "https://v3.football.api-sports.io"
USER_AGENT = "EdgeWise/1.0 personal statistical research"


def _api_request(
    endpoint: str, api_key: str, params: dict | None = None
) -> dict:
    url = f"{API_URL}/{endpoint}"
    if params:
        qs = "&".join(f"{k}={v}" for k, v in params.items())
        url = f"{url}?{qs}"
    request = urllib.request.Request(url, headers={
        "User-Agent": USER_AGENT,
        "x-rapidapi-key": api_key,
        "x-rapidapi-host": "v3.football.api-sports.io",
    })
    with urllib.request.urlopen(request, timeout=15) as response:
        data = json.loads(response.read().decode())
    if data.get("errors"):
        raise ValueError(f"API-Football error: {data['errors']}")
    return data


def fetch_injuries(
    league_id: int, season: int, api_key: str, cache_dir: Path
) -> pd.DataFrame:
    """Fetch injuries for a league-season. Rate-limited to free tier (100/day)."""
    if not api_key:
        return pd.DataFrame()

    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / f"injuries_{league_id}_{season}.csv"
    if cache_path.exists():
        return pd.read_csv(cache_path)

    try:
        data = _api_request("injuries", api_key, {
            "league": str(league_id),
            "season": str(season),
        })
    except Exception:
        return pd.DataFrame()

    records = []
    for item in data.get("response", []):
        player = item.get("player", {})
        team = item.get("team", {})
        fixture = item.get("fixture", {})
        records.append({
            "player_id": player.get("id"),
            "player_name": player.get("name", ""),
            "team_id": team.get("id"),
            "team_name": team.get("name", ""),
            "fixture_id": fixture.get("id"),
            "fixture_date": fixture.get("date", ""),
            "type": item.get("player", {}).get("type", ""),
            "reason": item.get("player", {}).get("reason", ""),
        })
    time.sleep(0.5)  # respect rate limits

    if records:
        frame = pd.DataFrame(records)
        frame.to_csv(cache_path, index=False)
        return frame
    return pd.DataFrame()


# League ID mapping for API-Football
LEAGUE_IDS = {
    "E0": 39,   # Premier League
    "SP1": 140, # La Liga
    "D1": 78,   # Bundesliga
    "I1": 135,  # Serie A
    "F1": 61,   # Ligue 1
}


def build_injury_features(
    matches: pd.DataFrame,
    league_code: str,
    api_key: str,
    cache_dir: Path,
) -> pd.DataFrame:
    """Add team-level injury count features before each match."""
    if not api_key or league_code not in LEAGUE_IDS:
        return matches

    league_id = LEAGUE_IDS[league_code]
    all_injuries = []

    # Fetch last 2 seasons
    for season_year in range(2023, 2026):
        try:
            injuries = fetch_injuries(league_id, season_year, api_key, cache_dir)
            if not injuries.empty:
                all_injuries.append(injuries)
        except Exception:
            continue

    if not all_injuries:
        return matches

    injury_frame = pd.concat(all_injuries, ignore_index=True)
    injury_frame["fixture_date"] = pd.to_datetime(
        injury_frame["fixture_date"], errors="coerce"
    )

    matches = matches.copy()
    matches["Date"] = pd.to_datetime(matches["Date"], errors="coerce")

    for side in ("Home", "Away"):
        col_name = f"{side.lower()}_injury_count"
        values = []
        for _, row in matches.iterrows():
            team = row[f"{side}Team"]
            match_date = row["Date"]
            count = len(injury_frame[
                (injury_frame["team_name"] == team) &
                (injury_frame["fixture_date"] <= match_date) &
                (injury_frame["fixture_date"] >= match_date - pd.Timedelta(days=60))
            ])
            values.append(count)
        matches[col_name] = values

    return matches
