from __future__ import annotations

import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

USER_AGENT = "EdgeWise/1.0 personal statistical research"

# HKO Open Data API base
HKO_BASE = "https://data.weather.gov.hk/weatherAPI/opendata"

# Nearby stations to racecourses
# Sha Tin: Sha Tin station (ST)
# Happy Valley: Hong Kong Observatory station (HKO) or Happy Valley specific
STATIONS = {
    "ST": "SHA",   # Sha Tin station
    "HV": "HKO",   # HK Observatory (closest to HV)
}

RACING_VENUE_LATLON = {
    "ST": (22.400, 114.205),
    "HV": (22.273, 114.180),
}


def fetch_hko_current_weather(cache_dir: Path, api_key: str = "") -> dict | None:
    """Fetch current weather from HKO. API key is optional for basic data."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_path = cache_dir / "hko_current.json"

    now = datetime.now(timezone.utc)
    if cache_path.exists():
        cached = json.loads(cache_path.read_text(encoding="utf-8"))
        cache_time = datetime.fromisoformat(
            cached.get("updateTime", "2000-01-01T00:00:00+08:00")
            .replace("Z", "+00:00")
        )
        if (now - cache_time).total_seconds() < 1800:  # 30-min cache
            return cached

    url = f"{HKO_BASE}/weather/currentWeather.xml"
    # Also try the JSON API endpoint
    json_url = (
        "https://data.weather.gov.hk/weatherAPI/opendata/weather.php"
        "?dataType=rhrread&lang=en"
    )

    try:
        request = urllib.request.Request(
            json_url, headers={"User-Agent": USER_AGENT}
        )
        with urllib.request.urlopen(request, timeout=15) as response:
            data = json.loads(response.read().decode())
        data["_cached_at"] = now.isoformat()
        cache_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        return data
    except Exception:
        return None


def extract_venue_weather(
    cache_dir: Path, venue: str = "ST"
) -> dict[str, float]:
    """Extract temperature, humidity, rainfall for a specific venue."""
    data = fetch_hko_current_weather(cache_dir)
    if not data:
        return {}

    temperature = float("nan")
    humidity = float("nan")
    rainfall = 0.0

    # Parse temperature data
    temp_data = data.get("temperature", {}).get("data", [])
    for station in temp_data:
        if station.get("place") in ("Sha Tin", "ShaTin", "沙田"):
            temperature = float(station.get("value", float("nan")))
            break

    # Parse humidity
    hum_data = data.get("humidity", {}).get("data", [])
    if hum_data:
        humidity = float(hum_data[0].get("value", float("nan")))

    # Parse rainfall
    rain_data = data.get("rainfall", {}).get("data", [])
    for station in rain_data:
        if station.get("place") in ("Sha Tin", "ShaTin", "沙田"):
            rainfall = float(station.get("max", 0))
            break

    return {
        "temp_celsius": temperature if temperature == temperature else 25.0,
        "humidity_pct": humidity if humidity == humidity else 75.0,
        "rainfall_mm": rainfall,
    }


def add_hko_features(
    races: list[dict], cache_dir: Path
) -> list[dict]:
    """Add HKO weather features to upcoming race predictions."""
    if not races:
        return races

    for race in races:
        venue = race.get("venue", "ST")
        weather = extract_venue_weather(cache_dir, venue)

        race["weather_temp_c"] = weather.get("temp_celsius", 25.0)
        race["weather_humidity"] = weather.get("humidity_pct", 75.0)
        race["weather_rainfall_mm"] = weather.get("rainfall_mm", 0.0)

        # Derive going prediction
        rainfall = weather.get("rainfall_mm", 0.0)
        if rainfall > 10:
            race["predicted_going"] = "SOFT"
        elif rainfall > 3:
            race["predicted_going"] = "YIELDING"
        else:
            race["predicted_going"] = "GOOD"

    return races
