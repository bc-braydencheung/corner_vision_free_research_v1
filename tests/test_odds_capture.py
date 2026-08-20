from __future__ import annotations

import json
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tempfile import TemporaryDirectory

from forecasting.odds_capture import (
    CaptureError,
    Quote,
    append,
    dart_document,
    football_profiles,
    football_quotes,
    last_seen,
    racing_quotes,
)

ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 8, 17, 4, 0, tzinfo=timezone.utc)


def _match(kick_off: str, profile: str = "50000100") -> dict[str, object]:
    return {
        "id": "50072568",
        "kickOffTime": kick_off,
        "tournament": {"nameProfileId": profile},
        "homeTeam": {"name_ch": "主隊"},
        "awayTeam": {"name_ch": "客隊"},
        "foPools": [
            {
                "oddsType": "CHL",
                "lines": [
                    {
                        "condition": "8.5",
                        "status": "AVAILABLE",
                        "combinations": [
                            {"str": "H", "currentOdds": "1.87"},
                            {"str": "L", "currentOdds": "1.83"},
                        ],
                    }
                ],
            },
            {
                "oddsType": "HIL",
                "lines": [
                    {
                        "condition": "2.5",
                        "combinations": [{"str": "H", "currentOdds": "1.90"}],
                    }
                ],
            },
        ],
    }


class DartDocumentTest(unittest.TestCase):
    def test_reads_the_whitelisted_documents_from_the_app_sources(self) -> None:
        football = dart_document(
            ROOT / "lib/services/hkjc_football_service.dart", "matchListQuery"
        )
        self.assertIn("query matchList(", football)
        self.assertIn("currentOdds", football)
        racing = dart_document(
            ROOT / "lib/services/hkjc_racing_odds_service.dart", "poolQuery"
        )
        self.assertIn("oddsNodes", racing)

    def test_missing_constant_is_an_error(self) -> None:
        with self.assertRaises(CaptureError):
            dart_document(
                ROOT / "lib/services/hkjc_football_service.dart", "noSuchQuery"
            )

    def test_profiles_match_the_app(self) -> None:
        profiles = football_profiles(
            ROOT / "lib/services/hkjc_football_service.dart"
        )
        self.assertEqual(profiles.get("50000051"), "E0")
        self.assertEqual(profiles.get("50000100"), "SP1")
        self.assertEqual(profiles.get("50000058"), "F1")
        self.assertEqual(profiles.get("50000069"), "I1")


class FootballQuotesTest(unittest.TestCase):
    profiles = {"50000100": "SP1"}

    def test_keeps_corner_pools_inside_the_horizon(self) -> None:
        quotes = football_quotes(
            {"data": {"matches": [_match("2026-08-17T20:00:00.000+08:00")]}},
            self.profiles,
            NOW,
        )
        self.assertEqual(len(quotes), 1)
        quote = quotes[0]
        self.assertEqual(quote.key, "football:50072568:CHL:8.5")
        self.assertEqual(quote.values, {"H": 1.87, "L": 1.83})
        self.assertEqual(quote.payload["league"], "SP1")
        self.assertEqual(quote.payload["market"], "CHL")

    def test_drops_untracked_tournaments_and_distant_fixtures(self) -> None:
        self.assertEqual(
            football_quotes(
                {
                    "data": {
                        "matches": [
                            _match("2026-08-17T20:00:00.000+08:00", "99999999")
                        ]
                    }
                },
                self.profiles,
                NOW,
            ),
            [],
        )
        self.assertEqual(
            football_quotes(
                {"data": {"matches": [_match("2026-09-30T20:00:00.000+08:00")]}},
                self.profiles,
                NOW,
            ),
            [],
        )

    def test_malformed_payloads_do_not_raise(self) -> None:
        self.assertEqual(football_quotes({}, self.profiles, NOW), [])
        self.assertEqual(
            football_quotes({"data": {"matches": None}}, self.profiles, NOW), []
        )
        self.assertEqual(
            football_quotes(
                {"data": {"matches": [{"tournament": {}, "kickOffTime": ""}]}},
                self.profiles,
                NOW,
            ),
            [],
        )

    def test_suspended_odds_are_not_recorded(self) -> None:
        match = _match("2026-08-17T20:00:00.000+08:00")
        pools = match["foPools"]
        assert isinstance(pools, list)
        pools[0]["lines"][0]["combinations"] = [
            {"str": "H", "currentOdds": "---"},
            {"str": "L", "currentOdds": "0"},
        ]
        self.assertEqual(football_quotes({"data": {"matches": [match]}}, self.profiles, NOW), [])


class RacingQuotesTest(unittest.TestCase):
    pools = [
        {
            "oddsType": "WIN",
            "status": "OPEN",
            "leg": {"races": [3]},
            "oddsNodes": [
                {"combString": "1", "oddsValue": "4.5"},
                {"combString": "2", "oddsValue": "SCR"},
            ],
        },
        {
            "oddsType": "QIN",
            "leg": {"races": [3]},
            "oddsNodes": [{"combString": "1-2", "oddsValue": "12"}],
        },
    ]

    def test_keeps_win_and_place_only(self) -> None:
        quotes = racing_quotes(
            {"date": "2026-08-17", "venueCode": "ST"}, self.pools, NOW
        )
        self.assertEqual(len(quotes), 1)
        self.assertEqual(quotes[0].key, "racing:2026-08-17:ST:3:WIN")
        self.assertEqual(quotes[0].values, {"1": 4.5})
        self.assertEqual(quotes[0].payload["raceId"], "HK:2026-08-17:ST:3")


class AppendTest(unittest.TestCase):
    def _quote(self, odds: dict[str, float]) -> Quote:
        return Quote(key="k", values=odds, payload={"odds": odds})

    def test_appends_and_preserves_capture_times(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "odds" / "history.jsonl"
            self.assertEqual(append(path, [self._quote({"H": 1.9})], NOW), 1)
            # Same quote inside the minimum gap is not recorded twice.
            self.assertEqual(
                append(path, [self._quote({"H": 1.9})], NOW + timedelta(minutes=1)),
                0,
            )
            # A move is recorded immediately.
            later = NOW + timedelta(minutes=2)
            self.assertEqual(append(path, [self._quote({"H": 1.8})], later), 1)
            # An unchanged quote is still refreshed once the gap elapses.
            much_later = NOW + timedelta(minutes=30)
            self.assertEqual(
                append(path, [self._quote({"H": 1.8})], much_later), 1
            )
            rows = [
                json.loads(row)
                for row in path.read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(
                [row["capturedAt"] for row in rows],
                [
                    "2026-08-17T04:00:00Z",
                    "2026-08-17T04:02:00Z",
                    "2026-08-17T04:30:00Z",
                ],
            )
            self.assertEqual([row["odds"]["H"] for row in rows], [1.9, 1.8, 1.8])

    def test_corrupt_lines_are_skipped_without_losing_the_file(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "history.jsonl"
            path.write_text("not json\n", encoding="utf-8")
            self.assertEqual(last_seen(path), {})
            self.assertEqual(append(path, [self._quote({"H": 1.9})], NOW), 1)
            self.assertIn("not json", path.read_text(encoding="utf-8"))


class WorkflowTest(unittest.TestCase):
    def test_schedule_is_quarter_hourly_and_needs_no_secret(self) -> None:
        path = ROOT / ".github/workflows/capture-odds.yml"
        if not path.exists():
            self.skipTest("capture-odds.yml is applied separately")
        workflow = path.read_text(encoding="utf-8")
        self.assertIn('cron: "*/15 * * * *"', workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn("odds-history", workflow)
        # Only the built-in token is used: no paid or private credential.
        self.assertEqual(workflow.count("secrets."), workflow.count("secrets.GITHUB_TOKEN"))


if __name__ == "__main__":  # pragma: no cover
    unittest.main()
