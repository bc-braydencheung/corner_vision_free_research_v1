from __future__ import annotations

import argparse
import bz2
import csv
import json
import re
from dataclasses import asdict, dataclass, replace
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable, Iterator, TextIO


LINE_PATTERN = re.compile(r"(\d+(?:\.\d+)?)")


@dataclass(frozen=True)
class CornerMarketSnapshot:
    market_id: str
    event_name: str
    market_name: str
    market_type: str
    captured_at: str
    market_time: str
    line: float
    over_odds: float
    under_odds: float
    match_id: str = ""
    is_closing: bool = False
    in_play: bool = False
    source: str = "Betfair Historical Data Basic"


@dataclass
class _MarketState:
    event_name: str = ""
    market_name: str = ""
    market_type: str = ""
    market_time: str = ""
    in_play: bool = False
    line: float | None = None
    runners: dict[int, str] | None = None
    prices: dict[int, float] | None = None

    def __post_init__(self) -> None:
        self.runners = self.runners or {}
        self.prices = self.prices or {}


def _open_text(path: Path) -> TextIO:
    if path.suffix == ".bz2":
        return bz2.open(path, mode="rt", encoding="utf-8")
    return path.open(encoding="utf-8")


def _iso_timestamp(value: object) -> str:
    if isinstance(value, (int, float)):
        return datetime.fromtimestamp(
            float(value) / 1000,
            tz=timezone.utc,
        ).isoformat()
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed.astimezone(timezone.utc).isoformat()


def _corner_line(market_name: str, runner_names: Iterable[str]) -> float | None:
    text = " ".join([market_name, *runner_names]).lower()
    if "corner" not in text:
        return None
    values = [float(value) for value in LINE_PATTERN.findall(text)]
    fractional = [value for value in values if value % 1 in (0.25, 0.5, 0.75)]
    return fractional[0] if fractional else None


def _direction(name: str) -> str | None:
    lowered = name.lower()
    if "over" in lowered or "or more" in lowered:
        return "over"
    if "under" in lowered or "or less" in lowered:
        return "under"
    return None


def parse_basic_stream(lines: Iterable[str]) -> list[CornerMarketSnapshot]:
    states: dict[str, _MarketState] = {}
    output: dict[tuple[str, str, float], CornerMarketSnapshot] = {}
    for line in lines:
        if not line.strip():
            continue
        message = json.loads(line)
        captured_at = _iso_timestamp(message["pt"])
        for change in message.get("mc", []):
            market_id = str(change["id"])
            state = states.setdefault(market_id, _MarketState())
            definition = change.get("marketDefinition")
            if definition:
                state.event_name = str(
                    definition.get("eventName", state.event_name)
                )
                state.market_name = str(definition.get("name", state.market_name))
                state.market_type = str(
                    definition.get("marketType", state.market_type)
                )
                state.market_time = str(
                    definition.get("marketTime", state.market_time)
                )
                state.in_play = bool(definition.get("inPlay", state.in_play))
                for runner in definition.get("runners", []):
                    runner_id = int(runner["id"])
                    runner_name = str(runner.get("name", runner_id))
                    state.runners[runner_id] = runner_name
                state.line = _corner_line(
                    state.market_name,
                    state.runners.values(),
                )
            for runner_change in change.get("rc", []):
                last_price = runner_change.get("ltp")
                if last_price is not None:
                    state.prices[int(runner_change["id"])] = float(last_price)
            if state.in_play or state.line is None or not state.market_time:
                continue
            directional_prices: dict[str, float] = {}
            for runner_id, name in state.runners.items():
                direction = _direction(name)
                price = state.prices.get(runner_id)
                if direction is not None and price is not None and price > 1:
                    directional_prices[direction] = price
            if directional_prices.keys() < {"over", "under"}:
                continue
            if datetime.fromisoformat(captured_at) >= datetime.fromisoformat(
                state.market_time.replace("Z", "+00:00")
            ):
                continue
            snapshot = CornerMarketSnapshot(
                market_id=market_id,
                event_name=state.event_name,
                market_name=state.market_name,
                market_type=state.market_type,
                captured_at=captured_at,
                market_time=_iso_timestamp(state.market_time),
                line=state.line,
                over_odds=directional_prices["over"],
                under_odds=directional_prices["under"],
            )
            output[(market_id, captured_at, state.line)] = snapshot
    snapshots = list(output.values())
    latest_keys = {
        (
            snapshot.market_id,
            snapshot.line,
            max(
                value.captured_at
                for value in snapshots
                if value.market_id == snapshot.market_id
                and value.line == snapshot.line
            ),
        )
        for snapshot in snapshots
        if states[snapshot.market_id].in_play
    }
    snapshots = [
        replace(
            snapshot,
            is_closing=(
                snapshot.market_id,
                snapshot.line,
                snapshot.captured_at,
            )
            in latest_keys,
        )
        for snapshot in snapshots
    ]
    return sorted(
        snapshots,
        key=lambda snapshot: (
            snapshot.market_time,
            snapshot.market_id,
            snapshot.captured_at,
            snapshot.line,
        ),
    )


def import_basic_files(paths: Iterable[Path]) -> list[CornerMarketSnapshot]:
    snapshots: list[CornerMarketSnapshot] = []
    for path in paths:
        with _open_text(path) as stream:
            snapshots.extend(parse_basic_stream(stream))
    unique = {
        (snapshot.market_id, snapshot.captured_at, snapshot.line): snapshot
        for snapshot in snapshots
    }
    return sorted(
        unique.values(),
        key=lambda snapshot: (
            snapshot.market_time,
            snapshot.market_id,
            snapshot.captured_at,
            snapshot.line,
        ),
    )


def attach_football_data_match_ids(
    snapshots: Iterable[CornerMarketSnapshot],
    fixture_paths: Iterable[Path],
) -> list[CornerMarketSnapshot]:
    fixtures: list[dict[str, str]] = []
    for fixture_path in fixture_paths:
        with fixture_path.open(newline="", encoding="utf-8-sig") as stream:
            fixtures.extend(csv.DictReader(stream))
    output: list[CornerMarketSnapshot] = []
    for snapshot in snapshots:
        market_date = datetime.fromisoformat(snapshot.market_time).date()
        teams = re.split(r"\s+(?:v|@)\s+", snapshot.event_name, maxsplit=1)
        matches = []
        if len(teams) == 2:
            event_home, event_away = map(_normalise_team, teams)
            for fixture in fixtures:
                fixture_date = datetime.strptime(
                    fixture["Date"],
                    "%d/%m/%Y",
                ).date()
                if abs(fixture_date - market_date) > timedelta(days=1):
                    continue
                if (
                    _normalise_team(fixture["HomeTeam"]) == event_home
                    and _normalise_team(fixture["AwayTeam"]) == event_away
                ):
                    matches.append(fixture)
        if len(matches) == 1:
            fixture = matches[0]
            fixture_date = datetime.strptime(
                fixture["Date"],
                "%d/%m/%Y",
            ).date()
            match_id = (
                f"{fixture['Div']}:{fixture_date.isoformat()}:"
                f"{fixture['HomeTeam']}:{fixture['AwayTeam']}"
            )
            output.append(replace(snapshot, match_id=match_id))
        else:
            output.append(snapshot)
    return output


def _normalise_team(value: str) -> str:
    aliases = {
        "manchester united": "man utd",
        "manchester city": "man city",
        "tottenham hotspur": "tottenham",
        "wolverhampton wanderers": "wolves",
        "newcastle united": "newcastle",
        "west ham united": "west ham",
        "brighton and hove albion": "brighton",
    }
    normalised = re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()
    return aliases.get(normalised, normalised)


def _expanded_paths(paths: Iterable[Path]) -> Iterator[Path]:
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.bz2"))
        else:
            yield path


def _football_data_paths(paths: Iterable[Path]) -> Iterator[Path]:
    for path in paths:
        if path.is_dir():
            yield from sorted(path.rglob("*.csv"))
        else:
            yield path


def write_csv(
    snapshots: Iterable[CornerMarketSnapshot],
    output_path: Path,
) -> None:
    merged: dict[tuple[str, str, float], CornerMarketSnapshot] = {}
    if output_path.exists():
        with output_path.open(newline="", encoding="utf-8") as stream:
            for row in csv.DictReader(stream):
                current = CornerMarketSnapshot(
                    market_id=row["market_id"],
                    event_name=row["event_name"],
                    market_name=row["market_name"],
                    market_type=row["market_type"],
                    captured_at=row["captured_at"],
                    market_time=row["market_time"],
                    line=float(row["line"]),
                    over_odds=float(row["over_odds"]),
                    under_odds=float(row["under_odds"]),
                    match_id=row.get("match_id", ""),
                    is_closing=row.get("is_closing", "False") == "True",
                    in_play=row.get("in_play", "False") == "True",
                    source=row["source"],
                )
                merged[(current.market_id, current.captured_at, current.line)] = (
                    current
                )
    for snapshot in snapshots:
        key = (snapshot.market_id, snapshot.captured_at, snapshot.line)
        current = merged.get(key)
        if current is not None and current != snapshot:
            raise ValueError("Betfair corner-market snapshots are immutable.")
        merged[key] = snapshot
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_path.with_suffix(f"{output_path.suffix}.tmp")
    fields = list(CornerMarketSnapshot.__dataclass_fields__)
    with temporary.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for snapshot in sorted(
            merged.values(),
            key=lambda value: (
                value.market_time,
                value.market_id,
                value.captured_at,
                value.line,
            ),
        ):
            writer.writerow(asdict(snapshot))
    temporary.replace(output_path)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Import free Betfair Basic football corner-market files."
    )
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--football-data", nargs="+", type=Path)
    args = parser.parse_args()
    snapshots = import_basic_files(_expanded_paths(args.inputs))
    if args.football_data is not None:
        snapshots = attach_football_data_match_ids(
            snapshots,
            _football_data_paths(args.football_data),
        )
    write_csv(snapshots, args.output)


if __name__ == "__main__":
    main()
