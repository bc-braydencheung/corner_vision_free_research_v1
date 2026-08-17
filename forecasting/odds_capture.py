"""Append-only capture of the public HKJC quotes.

The quotes themselves are free and public, but nobody publishes their history:
recording them with a capture time is what turns them into an opening quote, a
closing quote and the drift between the two. The app already does this on the
device, which only works while the phone is awake and the app installed, so the
same capture runs here on a schedule and accumulates the series regardless.

The GraphQL documents are read straight out of the Dart sources instead of being
copied: HKJC only serves its own whitelisted documents, so the app and this
collector must send byte-for-byte the same query.
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

ENDPOINT = "https://info.cld.hkjc.com/graphql/base/"
USER_AGENT = (
    "EdgeWise personal research collector/1.0 (low-frequency cached access)"
)

FOOTBALL_SOURCE = Path("lib/services/hkjc_football_service.dart")
RACING_SOURCE = Path("lib/services/hkjc_racing_odds_service.dart")

#: Head-to-head, total goals hi/lo and corner hi/lo pools.
FOOTBALL_ODDS_TYPES = ["HAD", "HIL", "CHL"]

#: Fixtures further away than this are not tracked yet.
HORIZON = timedelta(hours=60)

#: A line is re-recorded when it moved, or after this long regardless.
MINIMUM_GAP = timedelta(minutes=10)


class CaptureError(RuntimeError):
    """A capture pass could not reach or parse the public feed."""


def dart_document(source: Path, name: str) -> str:
    """Returns the raw string constant [name] declared in [source]."""
    text = source.read_text(encoding="utf-8")
    match = re.search(
        r"static const " + re.escape(name) + r" = r?'''(.*?)''';",
        text,
        re.DOTALL,
    )
    if match is None:
        raise CaptureError(f"{source}: no string constant named {name}")
    return match.group(1)


def post(query: str, variables: dict[str, object]) -> dict[str, object]:
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps({"query": query, "variables": variables}).encode(),
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/json",
            "Referer": "https://bet.hkjc.com/",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        body = response.read()
        if response.headers.get("Content-Encoding", "").lower() == "gzip":
            body = gzip.decompress(body)
    payload = json.loads(body.decode("utf-8"))
    errors = payload.get("errors")
    if errors:
        raise CaptureError(f"HKJC GraphQL: {errors[0].get('message')}")
    return payload


@dataclass(frozen=True)
class Quote:
    """One captured quote, keyed by whatever makes it unique."""

    key: str
    values: dict[str, float]
    payload: dict[str, object]


def _float(value: object) -> float | None:
    try:
        number = float(str(value))
    except (TypeError, ValueError):
        return None
    return number if number > 0 else None


def football_quotes(
    payload: dict[str, object], profiles: dict[str, str], now: datetime
) -> list[Quote]:
    """Corner (`CHL`) and head-to-head (`HAD`) quotes inside the horizon."""
    quotes: list[Quote] = []
    matches = ((payload.get("data") or {}).get("matches")) or []
    for match in matches:
        tournament = match.get("tournament") or {}
        league = profiles.get(tournament.get("nameProfileId") or "")
        if league is None:
            continue
        kick_off = _timestamp(match.get("kickOffTime"))
        if kick_off is None or not now - timedelta(hours=4) <= kick_off <= now + HORIZON:
            continue
        match_id = match.get("id") or ""
        for pool in match.get("foPools") or []:
            odds_type = pool.get("oddsType") or ""
            if odds_type not in ("CHL", "HAD"):
                continue
            for line in pool.get("lines") or []:
                values: dict[str, float] = {}
                for combination in line.get("combinations") or []:
                    odds = _float(combination.get("currentOdds"))
                    selection = (combination.get("selections") or [{}])[0]
                    name = combination.get("str") or selection.get("str") or ""
                    if odds is not None and name:
                        values[name] = odds
                if not values:
                    continue
                quotes.append(
                    Quote(
                        key=f"football:{match_id}:{odds_type}:"
                        f"{line.get('condition') or ''}",
                        values=values,
                        payload={
                            "market": odds_type,
                            "league": league,
                            "matchId": match_id,
                            "kickOffTime": match.get("kickOffTime"),
                            "condition": line.get("condition"),
                            "lineStatus": line.get("status"),
                            "home": (match.get("homeTeam") or {}).get("name_ch"),
                            "away": (match.get("awayTeam") or {}).get("name_ch"),
                            "odds": values,
                            "minutesToKickOff": round(
                                (kick_off - now).total_seconds() / 60
                            ),
                        },
                    )
                )
    return quotes


def racing_quotes(
    meeting: dict[str, object], pools: list[dict[str, object]], now: datetime
) -> list[Quote]:
    """Win and place pools of every race of one meeting."""
    date = meeting.get("date") or ""
    venue = meeting.get("venueCode") or ""
    quotes: list[Quote] = []
    for pool in pools:
        odds_type = pool.get("oddsType") or ""
        if odds_type not in ("WIN", "PLA"):
            continue
        races = ((pool.get("leg") or {}).get("races")) or []
        race_no = races[0] if races else None
        values = {}
        for node in pool.get("oddsNodes") or []:
            odds = _float(node.get("oddsValue"))
            comb = node.get("combString") or ""
            if odds is not None and comb:
                values[comb] = odds
        if not values or race_no is None:
            continue
        quotes.append(
            Quote(
                key=f"racing:{date}:{venue}:{race_no}:{odds_type}",
                values=values,
                payload={
                    "market": odds_type,
                    "raceId": f"HK:{date}:{venue}:{race_no}",
                    "date": date,
                    "venueCode": venue,
                    "raceNo": race_no,
                    "poolStatus": pool.get("status"),
                    "sellStatus": pool.get("sellStatus"),
                    "lastUpdateTime": pool.get("lastUpdateTime"),
                    "odds": values,
                },
            )
        )
    return quotes


def _timestamp(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def last_seen(path: Path) -> dict[str, tuple[datetime, dict[str, float]]]:
    """Latest stored quote of every key, so nothing is recorded twice."""
    seen: dict[str, tuple[datetime, dict[str, float]]] = {}
    if not path.exists():
        return seen
    with path.open(encoding="utf-8") as handle:
        for row in handle:
            row = row.strip()
            if not row:
                continue
            try:
                record = json.loads(row)
            except json.JSONDecodeError:
                continue
            captured = _timestamp(record.get("capturedAt"))
            key = record.get("key")
            odds = record.get("odds")
            if captured is None or not isinstance(key, str) or not isinstance(odds, dict):
                continue
            previous = seen.get(key)
            if previous is None or captured > previous[0]:
                seen[key] = (captured, {str(k): float(v) for k, v in odds.items()})
    return seen


def append(path: Path, quotes: list[Quote], now: datetime) -> int:
    """Appends the quotes that are new, and never rewrites a stored line."""
    seen = last_seen(path)
    fresh: list[Quote] = []
    for quote in quotes:
        previous = seen.get(quote.key)
        if previous is not None:
            captured, values = previous
            if now - captured < MINIMUM_GAP and values == quote.values:
                continue
        fresh.append(quote)
    if not fresh:
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        for quote in fresh:
            handle.write(
                json.dumps(
                    {
                        "key": quote.key,
                        "capturedAt": now.isoformat().replace("+00:00", "Z"),
                        **quote.payload,
                    },
                    ensure_ascii=False,
                    sort_keys=True,
                )
                + "\n"
            )
    return len(fresh)


def football_profiles(source: Path) -> dict[str, str]:
    """Tracked `nameProfileId` to league code, read from the Dart map."""
    text = source.read_text(encoding="utf-8")
    block = re.search(
        r"hkjcFootballProfiles = <String, String>\{(.*?)\};", text, re.DOTALL
    )
    if block is None:
        raise CaptureError(f"{source}: no hkjcFootballProfiles map")
    pairs = re.findall(r"'([^']+)'\s*:\s*'([^']+)'", block.group(1))
    return {profile: league for league, profile in pairs}


def tournament_ids(root: Path, profiles: dict[str, str]) -> list[str]:
    """Season ids on sale for the tracked tournaments.

    The `tournid` in the public URL is a stable `nameProfileId`, while the
    `matches` query needs the id of the season currently on sale.
    """
    payload = post(
        dart_document(root / FOOTBALL_SOURCE, "tournamentListQuery"), {}
    )
    listed = ((payload.get("data") or {}).get("tournamentList")) or []
    return [
        tournament["id"]
        for tournament in listed
        if tournament.get("nameProfileId") in profiles and tournament.get("id")
    ]


def capture_football(root: Path, out: Path, now: datetime) -> int:
    profiles = football_profiles(root / FOOTBALL_SOURCE)
    payload = post(
        dart_document(root / FOOTBALL_SOURCE, "matchListQuery"),
        {
            "startIndex": None,
            "endIndex": None,
            "startDate": None,
            "endDate": None,
            "matchIds": None,
            "tournIds": tournament_ids(root, profiles) or None,
            "fbOddsTypes": FOOTBALL_ODDS_TYPES,
            "fbOddsTypesM": FOOTBALL_ODDS_TYPES,
            "inplayOnly": False,
            "featuredMatchesOnly": False,
            "frontEndIds": None,
            "earlySettlementOnly": False,
            "showAllMatch": True,
        },
    )
    return append(
        out / "hkjc-football.jsonl",
        football_quotes(payload, profiles, now),
        now,
    )


def capture_racing(root: Path, out: Path, now: datetime) -> int:
    meeting_query = dart_document(root / RACING_SOURCE, "meetingQuery")
    pool_query = dart_document(root / RACING_SOURCE, "poolQuery")
    active = post(meeting_query, {"date": "", "venueCode": ""})
    meetings = ((active.get("data") or {}).get("activeMeetings")) or []
    open_meetings = [
        meeting
        for meeting in meetings
        if str(meeting.get("status") or "").upper() != "CLOSED"
    ] or meetings
    if not open_meetings:
        return 0
    meeting = sorted(
        open_meetings, key=lambda entry: str(entry.get("date") or ""), reverse=True
    )[0]
    date = str(meeting.get("date") or "")
    venue = str(meeting.get("venueCode") or "")
    if not date or not venue:
        return 0
    pools: list[dict[str, object]] = []
    for race in meeting.get("races") or []:
        race_no = race.get("no")
        if race_no is None:
            continue
        payload = post(
            pool_query,
            {
                "date": date,
                "venueCode": venue,
                "raceNo": race_no,
                "oddsTypes": ["WIN", "PLA"],
            },
        )
        for entry in ((payload.get("data") or {}).get("raceMeetings")) or []:
            pools.extend(entry.get("pmPools") or [])
    return append(
        out / "hkjc-racing.jsonl",
        racing_quotes({"date": date, "venueCode": venue}, pools, now),
        now,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--output", type=Path, default=Path("odds"))
    arguments = parser.parse_args(argv)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    football = racing = 0
    failures: list[str] = []
    try:
        football = capture_football(arguments.root, arguments.output, now)
    except Exception as error:  # noqa: BLE001 - one feed must not stop the other
        failures.append(f"football: {error}")
    try:
        racing = capture_racing(arguments.root, arguments.output, now)
    except Exception as error:  # noqa: BLE001
        failures.append(f"racing: {error}")
    print(f"appended football={football} racing={racing}")
    for failure in failures:
        print(f"warning: {failure}")
    # A feed with nothing on sale is normal, so only a total failure is an error.
    return 1 if len(failures) == 2 else 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
