from __future__ import annotations

import hashlib
import json
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path


FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
USER_AGENT = "EdgeWise/1.0 personal statistical research"


@dataclass(frozen=True)
class WeatherSnapshot:
    match_id: str
    captured_at: str
    valid_at: str
    latitude: float
    longitude: float
    temperature_c: float
    precipitation_probability: float
    wind_speed_kmh: float
    source: str = "Open-Meteo"


def parse_weather_response(
    match_id: str,
    captured_at: datetime,
    valid_at: datetime,
    payload: dict[str, object],
) -> WeatherSnapshot:
    hourly = payload["hourly"]
    if not isinstance(hourly, dict):
        raise ValueError("Open-Meteo hourly payload was missing.")
    times = [
        datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        for value in hourly["time"]
    ]
    target = valid_at.astimezone(timezone.utc)
    index = min(
        range(len(times)),
        key=lambda position: abs(
            (times[position].astimezone(timezone.utc) - target).total_seconds()
        ),
    )
    return WeatherSnapshot(
        match_id=match_id,
        captured_at=captured_at.astimezone(timezone.utc).isoformat(),
        valid_at=times[index].astimezone(timezone.utc).isoformat(),
        latitude=float(payload["latitude"]),
        longitude=float(payload["longitude"]),
        temperature_c=float(hourly["temperature_2m"][index]),
        precipitation_probability=float(
            hourly["precipitation_probability"][index]
        ),
        wind_speed_kmh=float(hourly["wind_speed_10m"][index]),
    )


def fetch_weather_snapshot(
    *,
    match_id: str,
    latitude: float,
    longitude: float,
    kickoff: datetime,
    cache_dir: Path,
) -> WeatherSnapshot:
    captured_at = datetime.now(timezone.utc)
    cache_dir.mkdir(parents=True, exist_ok=True)
    identity = f"{match_id}:{kickoff.isoformat()}:{latitude}:{longitude}"
    prefix = hashlib.sha256(identity.encode()).hexdigest()[:16]
    cached = [
        WeatherSnapshot(
            **json.loads(path.read_text(encoding="utf-8"))
        )
        for path in cache_dir.glob(f"{prefix}-*.json")
    ]
    if cached:
        previous = max(
            cached,
            key=lambda value: datetime.fromisoformat(value.captured_at),
        )
        previous_captured = datetime.fromisoformat(previous.captured_at)
        if captured_at - previous_captured <= timedelta(hours=6):
            return previous
    parameters = urllib.parse.urlencode(
        {
            "latitude": latitude,
            "longitude": longitude,
            "hourly": (
                "temperature_2m,precipitation_probability,wind_speed_10m"
            ),
            "timezone": "UTC",
            "forecast_days": 16,
        }
    )
    request = urllib.request.Request(
        f"{FORECAST_URL}?{parameters}",
        headers={"User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        payload = json.load(response)
    snapshot = parse_weather_response(
        match_id,
        captured_at,
        kickoff,
        payload,
    )
    captured_key = hashlib.sha256(snapshot.captured_at.encode()).hexdigest()[:8]
    output = cache_dir / f"{prefix}-{captured_key}.json"
    temporary = output.with_suffix(".tmp")
    temporary.write_text(
        json.dumps(asdict(snapshot), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temporary.replace(output)
    return snapshot
