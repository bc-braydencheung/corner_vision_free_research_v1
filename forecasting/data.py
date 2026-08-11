from __future__ import annotations

import csv
import hashlib
import io
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import date
from pathlib import Path

import pandas as pd

HISTORY_URL = "https://www.football-data.co.uk/mmz4281/{season}/{division}.csv"
FIXTURES_URL = "https://www.football-data.co.uk/fixtures.csv"
USER_AGENT = "EdgeWise/1.0 (+https://www.football-data.co.uk/)"


@dataclass(frozen=True)
class DataBundle:
    history: pd.DataFrame
    target_history: dict[str, pd.DataFrame]
    fixtures: pd.DataFrame
    fingerprint: str
    source_last_modified: str | None
    season_labels: dict[str, tuple[str, ...]]


@dataclass(frozen=True)
class LeagueConfig:
    code: str
    name: str
    support_code: str
    support_name: str
    country_url: str


LEAGUES = (
    LeagueConfig(
        code="E0",
        name="英超",
        support_code="E1",
        support_name="英冠",
        country_url="https://www.football-data.co.uk/englandm.php",
    ),
    LeagueConfig(
        code="SP1",
        name="西甲",
        support_code="SP2",
        support_name="西乙",
        country_url="https://www.football-data.co.uk/spainm.php",
    ),
    LeagueConfig(
        code="F1",
        name="法甲",
        support_code="F2",
        support_name="法乙",
        country_url="https://www.football-data.co.uk/francem.php",
    ),
    LeagueConfig(
        code="D1",
        name="德甲",
        support_code="D2",
        support_name="德乙",
        country_url="https://www.football-data.co.uk/germanym.php",
    ),
    LeagueConfig(
        code="I1",
        name="意甲",
        support_code="I2",
        support_name="意乙",
        country_url="https://www.football-data.co.uk/italym.php",
    ),
)


def season_codes(first_start_year: int = 2000, today: date | None = None) -> list[tuple[int, str, str]]:
    current = today or date.today()
    latest_start_year = current.year if current.month >= 7 else current.year - 1
    seasons: list[tuple[int, str, str]] = []
    for start_year in range(first_start_year, latest_start_year + 1):
        code = f"{start_year % 100:02d}{(start_year + 1) % 100:02d}"
        label = f"{start_year}/{(start_year + 1) % 100:02d}"
        seasons.append((start_year, code, label))
    return seasons


def _request(url: str) -> tuple[bytes, str | None]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read(), response.headers.get("Last-Modified")


def _read_csv(content: bytes) -> pd.DataFrame:
    text = content.decode("utf-8-sig", errors="replace")
    reader = csv.reader(io.StringIO(text))
    header = next(reader)
    counts: dict[str, int] = {}
    unique_header: list[str] = []
    for column in header:
        occurrence = counts.get(column, 0)
        unique_header.append(column if occurrence == 0 else f"{column}.{occurrence}")
        counts[column] = occurrence + 1
    width = len(header)
    rows: list[list[str]] = []
    for row in reader:
        if not row or not any(value.strip() for value in row):
            continue
        rows.append((row + [""] * width)[:width])
    return pd.DataFrame(rows, columns=unique_header)


def _normalise_matches(frame: pd.DataFrame, season: str, division: str) -> pd.DataFrame:
    required = {"Div", "Date", "HomeTeam", "AwayTeam", "HC", "AC"}
    if not required.issubset(frame.columns):
        return pd.DataFrame()

    matches = frame.loc[frame["Div"].eq(division)].copy()
    matches["Date"] = pd.to_datetime(
        matches["Date"],
        dayfirst=True,
        errors="coerce",
        format="mixed",
    )
    matches["Season"] = season
    matches["Division"] = division

    numeric_columns = (
        "FTHG",
        "FTAG",
        "HS",
        "AS",
        "HST",
        "AST",
        "HC",
        "AC",
        "AvgH",
        "AvgD",
        "AvgA",
        "B365H",
        "B365D",
        "B365A",
        "Avg>2.5",
        "Avg<2.5",
        "B365>2.5",
        "B365<2.5",
    )
    for column in numeric_columns:
        if column in matches:
            matches[column] = pd.to_numeric(matches[column], errors="coerce")

    matches = matches.dropna(subset=["Date", "HomeTeam", "AwayTeam", "HC", "AC"])
    matches["HC"] = matches["HC"].astype(int)
    matches["AC"] = matches["AC"].astype(int)
    return matches


def _normalise_fixtures(frame: pd.DataFrame) -> pd.DataFrame:
    required = {"Div", "Date", "HomeTeam", "AwayTeam"}
    if not required.issubset(frame.columns):
        return pd.DataFrame(columns=sorted(required))

    target_divisions = {league.code for league in LEAGUES}
    fixtures = frame.loc[frame["Div"].isin(target_divisions)].copy()
    fixtures["Date"] = pd.to_datetime(
        fixtures["Date"],
        dayfirst=True,
        errors="coerce",
        format="mixed",
    )
    numeric_columns = (
        "AvgH",
        "AvgD",
        "AvgA",
        "B365H",
        "B365D",
        "B365A",
        "Avg>2.5",
        "Avg<2.5",
        "B365>2.5",
        "B365<2.5",
    )
    for column in numeric_columns:
        if column in fixtures:
            fixtures[column] = pd.to_numeric(fixtures[column], errors="coerce")
    return fixtures.dropna(subset=["Date", "HomeTeam", "AwayTeam"]).sort_values("Date")


def load_data(cache_dir: Path, first_start_year: int = 2000) -> DataBundle:
    cache_dir.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    history_frames: list[pd.DataFrame] = []
    target_frames: dict[str, list[pd.DataFrame]] = {
        league.code: [] for league in LEAGUES
    }
    labels: dict[str, list[str]] = {league.code: [] for league in LEAGUES}
    divisions = tuple(
        division
        for league in LEAGUES
        for division in (league.code, league.support_code)
    )
    seasons = season_codes(first_start_year)
    latest_start_year = seasons[-1][0]
    latest_modified: str | None = None

    for start_year, code, label in seasons:
        for division in divisions:
            cache_path = cache_dir / f"{division}_{code}.csv"
            refresh = start_year >= latest_start_year - 1 or not cache_path.exists()
            try:
                if refresh:
                    content, modified = _request(
                        HISTORY_URL.format(season=code, division=division)
                    )
                    cache_path.write_bytes(content)
                    latest_modified = modified or latest_modified
                else:
                    content = cache_path.read_bytes()
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    continue
                raise

            frame = _normalise_matches(_read_csv(content), label, division)
            if frame.empty:
                continue
            digest.update(f"{division}:{code}".encode())
            digest.update(content)
            history_frames.append(frame)
            if division in target_frames:
                target_frames[division].append(frame)
                labels[division].append(label)

    missing = [
        league.name for league in LEAGUES if not target_frames[league.code]
    ]
    if missing:
        raise RuntimeError(
            "No history with HC/AC columns was downloaded for: " + ", ".join(missing)
        )

    fixtures_content, fixtures_modified = _request(FIXTURES_URL)
    fixtures = _normalise_fixtures(_read_csv(fixtures_content))
    digest.update(fixtures.to_csv(index=False).encode())
    history = pd.concat(history_frames, ignore_index=True).sort_values("Date").reset_index(drop=True)
    target_history = {
        division: pd.concat(frames, ignore_index=True)
        .sort_values("Date")
        .reset_index(drop=True)
        for division, frames in target_frames.items()
    }
    return DataBundle(
        history=history,
        target_history=target_history,
        fixtures=fixtures,
        fingerprint=digest.hexdigest(),
        source_last_modified=fixtures_modified or latest_modified,
        season_labels={
            division: tuple(division_labels)
            for division, division_labels in labels.items()
        },
    )
