from __future__ import annotations

import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

import pandas as pd

USER_AGENT = "EdgeWise/1.0 personal statistical research"
BASE_URL = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services"


def fetch_historical_weather(
    latitude: float,
    longitude: float,
    target_date: str,
    api_key: str,
    cache_dir: Path,
) -> dict | None:
    """Fetch historical weather for a specific date+location."""
    if not api_key:
        return None

    cache_dir.mkdir(parents=True, exist_ok=True)
    safe_date = target_date.replace("-", "")
    cache_path = cache_dir / f"vc_{latitude}_{longitude}_{safe_date}.json"

    if cache_path.exists():
        return json.loads(cache_path.read_text(encoding="utf-8"))

    url = (
        f"{BASE_URL}/timeline/{latitude},{longitude}/{target_date}/{target_date}"
        f"?unitGroup=metric&include=hours&key={api_key}"
        f"&contentType=json"
    )
    try:
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=15) as response:
            data = json.loads(response.read().decode())
    except Exception:
        return None

    cache_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    time.sleep(0.35)
    return data


# Stadium coordinates for the 5 major leagues
STADIUM_COORDS = {
    "E0": {  # Premier League - approximate London midpoint
        "default": (51.507, -0.128),
    },
    "SP1": {  # La Liga - Madrid midpoint
        "default": (40.417, -3.704),
    },
    "D1": {  # Bundesliga - central Germany
        "default": (51.166, 10.452),
    },
    "I1": {  # Serie A - Rome midpoint
        "default": (41.903, 12.496),
    },
    "F1": {  # Ligue 1 - Paris
        "default": (48.857, 2.352),
    },
}


def add_wind_features(
    matches: pd.DataFrame,
    league_code: str,
    api_key: str,
    cache_dir: Path,
) -> pd.DataFrame:
    """Add historical wind speed/direction features for each match."""
    if not api_key or league_code not in STADIUM_COORDS:
        return matches

    lat, lon = STADIUM_COORDS[league_code]["default"]
    matches = matches.copy()
    matches["Date"] = pd.to_datetime(matches["Date"], errors="coerce")

    wind_speeds = []
    wind_dirs = []
    humidity_vals = []

    for _, row in matches.iterrows():
        match_date = row["Date"]
        if pd.isna(match_date):
            wind_speeds.append(float("nan"))
            wind_dirs.append(float("nan"))
            humidity_vals.append(float("nan"))
            continue

        date_str = match_date.strftime("%Y-%m-%d")
        data = fetch_historical_weather(lat, lon, date_str, api_key, cache_dir)

        ws, wd, hum = float("nan"), float("nan"), float("nan")
        if data and "days" in data:
            day_data = data["days"][0] if data["days"] else {}
            hours = day_data.get("hours", [])
            if hours:
                # Average the hours around kickoff (typically 15:00 local)
                relevant = hours[12:18] if len(hours) > 12 else hours
                ws_vals = [h.get("windspeed", float("nan")) for h in relevant]
                wd_vals = [h.get("winddir", float("nan")) for h in relevant]
                h_vals = [h.get("humidity", float("nan")) for h in relevant]
                ws = sum(v for v in ws_vals if v == v) / max(
                    sum(1 for v in ws_vals if v == v), 1
                )
                wd = sum(v for v in wd_vals if v == v) / max(
                    sum(1 for v in wd_vals if v == v), 1
                )
                hum = sum(v for v in h_vals if v == v) / max(
                    sum(1 for v in h_vals if v == v), 1
                )

        wind_speeds.append(ws)
        wind_dirs.append(wd)
        humidity_vals.append(hum)

    matches["wind_speed_kmh"] = wind_speeds
    matches["wind_direction"] = wind_dirs
    matches["humidity_pct"] = humidity_vals

    for col in ("wind_speed_kmh", "wind_direction", "humidity_pct"):
        med = matches[col].median()
        matches[col] = matches[col].fillna(med if not pd.isna(med) else 0)

    return matches
