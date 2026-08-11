from __future__ import annotations

import json
import unittest
import bz2
from datetime import date, timedelta
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

import pandas as pd

from forecasting.data import DataBundle, LEAGUES, _read_csv, season_codes
from forecasting.betfair_historical import (
    attach_football_data_match_ids,
    import_basic_files,
    parse_basic_stream,
)
from forecasting.features import FeatureBuilder, feature_columns
from forecasting.football_market import (
    FootballMarketBlend,
    add_two_way_market_probabilities,
    apply_conservative_probabilities as apply_football_conservative,
    calibration_lower_multipliers as football_calibration_lower_multipliers,
    policy_selections as football_policy_selections,
    select_pre_match_snapshots,
    select_trade_policy as select_football_trade_policy,
)
from forecasting.football_mobile_seed import build_football_mobile_seed
from forecasting.model import (
    ForecastModel,
    TargetModel,
    over_probability,
    prediction_interval,
)
from forecasting.open_meteo import parse_weather_response
from forecasting.pipeline import _historical_drift
from forecasting.hkjc import (
    HKJCScraper,
    merge_bilingual_race_card,
    parse_local_result,
    parse_race_card,
)
from forecasting.racing import build_racing_payload
from forecasting.racing_model import (
    RacingFeatureBuilder,
    build_predictions,
    train_racing_model,
)
from forecasting.racing_market import (
    MarketBlend,
    add_market_probabilities,
    apply_conservative_probabilities,
    blend_probabilities,
    calibration_lower_multipliers,
    select_trade_policy,
)


class SeasonCodeTests(unittest.TestCase):
    def test_season_codes_roll_over_in_july(self) -> None:
        june = season_codes(2024, date(2026, 6, 30))
        july = season_codes(2024, date(2026, 7, 1))
        self.assertEqual(june[-1], (2025, "2526", "2025/26"))
        self.assertEqual(july[-1], (2026, "2627", "2026/27"))

    def test_csv_reader_handles_duplicate_headers_and_trailing_columns(self) -> None:
        frame = _read_csv(b"Team,Odds,Odds\nAlpha,2.1,2.2,,,\n")
        self.assertEqual(frame.columns.tolist(), ["Team", "Odds", "Odds.1"])
        self.assertEqual(frame.iloc[0].tolist(), ["Alpha", "2.1", "2.2"])

    def test_supported_leagues_exclude_japan_and_australia(self) -> None:
        self.assertEqual(
            [league.code for league in LEAGUES],
            ["E0", "SP1", "F1", "D1", "I1"],
        )

    def test_mobile_seed_uses_compact_deterministic_match_rows(self) -> None:
        history = pd.DataFrame(
            [
                {
                    "Division": "E0",
                    "Date": pd.Timestamp("2026-07-13"),
                    "HomeTeam": "Alpha",
                    "AwayTeam": "Beta",
                    "HC": 7,
                    "AC": 4,
                    "FTHG": 2,
                    "FTAG": 1,
                }
            ]
        )
        payload = build_football_mobile_seed(
            DataBundle(
                history=history,
                target_history={},
                fixtures=pd.DataFrame(),
                fingerprint="test",
                source_last_modified=None,
                season_labels={},
            )
        )

        self.assertEqual(
            payload["rows"][0][:8],
            ["E0", "2026-07-13", "Alpha", "Beta", 7, 4, 2, 1],
        )
        self.assertEqual(len(payload["datasetVersion"]), 16)


class LeakageTests(unittest.TestCase):
    def test_current_match_targets_do_not_change_its_features(self) -> None:
        base = pd.DataFrame(
            [
                {
                    "Date": pd.Timestamp("2024-08-01"),
                    "Season": "2024/25",
                    "HomeTeam": "Alpha",
                    "AwayTeam": "Beta",
                    "HC": 4,
                    "AC": 6,
                    "FTHG": 1,
                    "FTAG": 1,
                    "HS": 12,
                    "AS": 11,
                    "HST": 4,
                    "AST": 4,
                },
                {
                    "Date": pd.Timestamp("2024-08-08"),
                    "Season": "2024/25",
                    "HomeTeam": "Beta",
                    "AwayTeam": "Alpha",
                    "HC": 3,
                    "AC": 5,
                    "FTHG": 0,
                    "FTAG": 2,
                    "HS": 8,
                    "AS": 15,
                    "HST": 2,
                    "AST": 6,
                },
            ]
        )
        altered = base.copy()
        altered.loc[1, ["HC", "AC", "HS", "AS", "HST", "AST"]] = [15, 0, 30, 1, 20, 0]
        first = FeatureBuilder().fit_transform_history(base)
        second = FeatureBuilder().fit_transform_history(altered)
        columns = feature_columns(first)
        pd.testing.assert_series_equal(first.loc[1, columns], second.loc[1, columns])

    def test_championship_history_primes_promoted_team_features(self) -> None:
        rows: list[dict[str, object]] = []
        for index in range(8):
            rows.append(
                {
                    "Date": pd.Timestamp("2024-01-01") + pd.Timedelta(days=index * 7),
                    "Season": "2023/24",
                    "Division": "E1",
                    "HomeTeam": "Alpha",
                    "AwayTeam": f"Support {index}",
                    "HC": 8,
                    "AC": 3,
                    "FTHG": 2,
                    "FTAG": 0,
                    "HS": 17,
                    "AS": 8,
                    "HST": 6,
                    "AST": 2,
                }
            )
        rows.append(
            {
                "Date": pd.Timestamp("2024-08-10"),
                "Season": "2024/25",
                "Division": "E0",
                "HomeTeam": "Alpha",
                "AwayTeam": "Premier",
                "HC": 4,
                "AC": 5,
                "FTHG": 1,
                "FTAG": 1,
                "HS": 11,
                "AS": 12,
                "HST": 4,
                "AST": 4,
            }
        )
        features = FeatureBuilder().fit_transform_history(pd.DataFrame(rows))
        self.assertEqual(len(features), 1)
        self.assertGreater(features.loc[0, "home_support_share"], 0.9)
        self.assertEqual(features.loc[0, "home_promoted_flag"], 1.0)
        self.assertGreater(features.loc[0, "home_corner_for_dynamic"], 5.15)

    def test_second_division_configuration_is_league_specific(self) -> None:
        rows: list[dict[str, object]] = []
        for index in range(8):
            rows.append(
                {
                    "Date": pd.Timestamp("2024-01-01") + pd.Timedelta(days=index * 7),
                    "Season": "2023/24",
                    "Division": "SP2",
                    "HomeTeam": "Promoted",
                    "AwayTeam": f"Second {index}",
                    "HC": 7,
                    "AC": 3,
                    "FTHG": 1,
                    "FTAG": 0,
                }
            )
        rows.append(
            {
                "Date": pd.Timestamp("2024-08-10"),
                "Season": "2024/25",
                "Division": "SP1",
                "HomeTeam": "Promoted",
                "AwayTeam": "Top",
                "HC": 4,
                "AC": 4,
                "FTHG": 1,
                "FTAG": 1,
            }
        )
        features = FeatureBuilder("SP1", "SP2").fit_transform_history(
            pd.DataFrame(rows)
        )
        self.assertEqual(features.loc[0, "home_promoted_flag"], 1.0)
        self.assertGreater(features.loc[0, "home_support_share"], 0.9)


class DistributionTests(unittest.TestCase):
    def test_over_probability_decreases_as_line_rises(self) -> None:
        probabilities = [over_probability(10.2, line, 0.08) for line in (8.5, 9.5, 10.5)]
        self.assertGreater(probabilities[0], probabilities[1])
        self.assertGreater(probabilities[1], probabilities[2])

    def test_prediction_interval_contains_non_negative_counts(self) -> None:
        lower, upper = prediction_interval(10.2, 0.08)
        self.assertGreaterEqual(lower, 0)
        self.assertGreater(upper, lower)

    def test_calibrated_distribution_is_coherent(self) -> None:
        target = TargetModel("dynamic", (), "baseline_total_corners")
        model = ForecastModel(
            candidate="dynamic",
            feature_names=(),
            home_model=target,
            away_model=target,
            total_model=target,
            dispersion=0.08,
            calibration={
                7.5: (0.1, 0.9),
                9.5: (0.0, 1.0),
                12.5: (-0.1, 1.1),
            },
            interval_offsets=(-4.0, 4.0),
            metrics={},
            out_of_fold=pd.DataFrame(),
        )
        distribution = model.total_distribution(10.2)
        self.assertAlmostEqual(sum(distribution), 1.0)
        self.assertTrue(all(value >= 0 for value in distribution))
        self.assertGreater(
            model.over_probability(10.2, 8.5),
            model.over_probability(10.2, 9.5),
        )


class DriftTests(unittest.TestCase):
    @staticmethod
    def _model(actual: list[float], predicted: list[float]) -> ForecastModel:
        count = len(actual)
        target = TargetModel("dynamic", (), "baseline_total_corners")
        return ForecastModel(
            candidate="test",
            feature_names=(),
            home_model=target,
            away_model=target,
            total_model=target,
            dispersion=0.12,
            calibration={},
            interval_offsets=(0, 0),
            metrics={},
            out_of_fold=pd.DataFrame(
                {
                    "Date": pd.date_range("2025-01-01", periods=count),
                    "TotalCorners": actual,
                    "PredictedTotalCorners": predicted,
                }
            ),
        )

    def test_historical_drift_requires_reference_window(self) -> None:
        model = self._model([10] * 100, [10] * 100)
        self.assertEqual(_historical_drift(model)["status"], "insufficient")

    def test_historical_drift_stops_after_large_recent_error(self) -> None:
        model = self._model([10] * 100 + [16] * 100, [10] * 200)
        drift = _historical_drift(model)
        self.assertEqual(drift["status"], "stop")
        self.assertEqual(drift["referenceMatches"], 100)
        self.assertEqual(drift["recentMatches"], 100)


class RacingContractTests(unittest.TestCase):
    def test_historical_candidates_include_holiday_meetings(self) -> None:
        scraper = HKJCScraper(Path("unused"))
        with patch.object(HKJCScraper, "discover_dates", return_value=[]):
            candidates = scraper.candidate_dates(
                date(2022, 7, 15),
                date(2022, 7, 17),
            )
        self.assertEqual(
            candidates,
            [date(2022, 7, 15), date(2022, 7, 16), date(2022, 7, 17)],
        )

    def test_racing_is_unavailable_without_verified_source(self) -> None:
        payload = build_racing_payload()
        self.assertFalse(payload["available"])
        self.assertEqual(payload["races"], [])

    def test_racing_contract_rejects_invalid_payload(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "latest.json"
            path.write_text('{"races": [{"raceId": "broken"}]}', encoding="utf-8")
            with self.assertRaises(ValueError):
                build_racing_payload(path)

    def test_hkjc_result_parser_reads_full_field(self) -> None:
        html = """
        <table class="js_racecard"><tr><td>Sha Tin:</td></tr></table>
        <table>
          <tr><td>RACE 1 (1)</td></tr>
          <tr><td>Class 4 - 1200M - (60-40)</td><td>Going :</td><td>GOOD</td></tr>
          <tr><td>TEST HANDICAP</td><td>Course :</td><td>TURF - "A" Course</td></tr>
        </table>
        <table class="table_bd draggable">
          <tr><td>Pla.</td><td>Horse No.</td><td>Horse</td><td>Jockey</td>
          <td>Trainer</td><td>Act. Wt.</td><td>Declar. Horse Wt.</td>
          <td>Dr.</td><td>LBW</td><td>Running Position</td>
          <td>Finish Time</td><td>Win Odds</td></tr>
          <tr><td>1</td><td>2</td><td><a href="?HorseId=HK_2024_K001">ALPHA (K001)</a></td>
          <td>J One</td><td>T One</td><td>128</td><td>1100</td><td>3</td>
          <td>---</td><td>2 1</td><td>1:09.10</td><td>4.5</td></tr>
          <tr><td>2</td><td>1</td><td><a href="?HorseId=HK_2023_J002">BETA (J002)</a></td>
          <td>J Two</td><td>T Two</td><td>130</td><td>1088</td><td>1</td>
          <td>1</td><td>1 2</td><td>1:09.20</td><td>2.8</td></tr>
        </table>
        """
        rows = parse_local_result(html, date(2026, 7, 1))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["horse_id"], "2024_K001")
        self.assertEqual(rows[0]["field_size"], 2)
        self.assertEqual(rows[0]["won"], 1)

    def test_hkjc_race_card_parser_reads_declared_runners(self) -> None:
        html = """
        <div class="f_fs13">Race 1 - TEST HANDICAP Wednesday, July 15, 2026,
        Happy Valley, 18:30 Turf, "C" Course, 1650M, Good Prize Money:
        $875,000, Rating: 40-0, Class 5</div>
        <table class="starter"><tr>
          <th>Horse No.</th><th>Last 6 Runs</th><th>Colour</th><th>Horse</th>
          <th>Brand</th><th>Wt.</th><th>Jockey</th><th>Over</th><th>Draw</th>
          <th>Trainer</th><th>Int</th><th>Rtg.</th><th>Change</th>
          <th>Horse Wt.</th><th>Change</th><th>Time</th><th>Age</th>
          <th>WFA</th><th>Sex</th><th>Stakes</th><th>Priority</th>
          <th>Days</th><th>Gear</th><th>Owner</th><th>Sire</th><th>Dam</th>
          <th>Import</th></tr>
          <tr><td>1</td><td>2/3/4</td><td></td>
          <td><a href="?horseid=HK_2024_K001">ALPHA</a></td><td>K001</td>
          <td>128</td><td>J One</td><td></td><td>3</td><td>T One</td>
          <td>-</td><td>40</td><td>-2</td><td>1100</td><td>+2</td>
          <td></td><td>4</td><td>-</td><td>g</td><td>0</td><td></td>
          <td>14</td><td>TT</td><td>Owner</td><td>Sire</td><td>Dam</td>
          <td>PPG</td></tr>
          <tr><td>2</td><td>5/6</td><td></td>
          <td><a href="?horseid=HK_2023_J002">BETA</a></td><td>J002</td>
          <td>125</td><td>J Two</td><td></td><td>1</td><td>T Two</td>
          <td>-</td><td>37</td><td>0</td><td>1080</td><td>-1</td>
          <td></td><td>5</td><td>-</td><td>g</td><td>0</td><td></td>
          <td>21</td><td></td><td>Owner</td><td>Sire</td><td>Dam</td>
          <td>PP</td></tr></table>
        """
        race = parse_race_card(html)
        self.assertIsNotNone(race)
        assert race is not None
        self.assertEqual(race["race_id"], "HK:2026-07-15:HV:1")
        self.assertEqual(len(race["runners"]), 2)
        chinese = {
            **race,
            "runners": [
                {**runner, "horse_name": f"中文馬{index}"}
                for index, runner in enumerate(race["runners"], start=1)
            ],
        }
        bilingual = merge_bilingual_race_card(race, chinese)
        self.assertEqual(
            bilingual["runners"][0]["horse_name_english"],
            "ALPHA",
        )
        self.assertEqual(
            bilingual["runners"][0]["horse_name_chinese"],
            "中文馬1",
        )

    def test_racing_features_do_not_use_current_result(self) -> None:
        rows = []
        for race_number in range(2):
            for runner in range(4):
                rows.append(
                    {
                        "race_id": f"HK:2026-01-0{race_number + 1}:ST:1",
                        "date": f"2026-01-0{race_number + 1}",
                        "venue": "Sha Tin",
                        "venue_code": "ST",
                        "race_number": 1,
                        "distance": 1200,
                        "race_class": "4",
                        "surface": "TURF",
                        "course": '"A" Course',
                        "horse_id": f"H{runner}",
                        "horse_name": f"Horse {runner}",
                        "jockey": f"J{runner}",
                        "trainer": f"T{runner}",
                        "weight": 125 + runner,
                        "draw": runner + 1,
                        "finish_position": runner + 1,
                        "field_size": 4,
                        "won": int(runner == 0),
                        "placed": int(runner < 2),
                    }
                )
        altered = pd.DataFrame(rows)
        original = altered.copy()
        mask = altered["race_id"].str.contains("2026-01-02")
        altered.loc[mask, "finish_position"] = [4, 3, 2, 1]
        altered.loc[mask, "won"] = [0, 0, 0, 1]
        first = RacingFeatureBuilder().fit_transform(original)
        second = RacingFeatureBuilder().fit_transform(altered)
        feature_names = [
            column
            for column in first.columns
            if column.endswith("_rate") or column.endswith("_score")
        ]
        pd.testing.assert_frame_equal(
            first.loc[mask, feature_names].reset_index(drop=True),
            second.loc[mask, feature_names].reset_index(drop=True),
        )

    def test_racing_probabilities_are_normalised_within_race(self) -> None:
        rows = []
        for race_number in range(100):
            race_date = date(2025, 1, 1) + timedelta(days=race_number * 2)
            for runner in range(8):
                finish = ((runner + race_number) % 8) + 1
                rows.append(
                    {
                        "race_id": f"HK:{race_date}:ST:1",
                        "date": race_date.isoformat(),
                        "venue": "Sha Tin",
                        "venue_code": "ST",
                        "race_number": 1,
                        "distance": 1200,
                        "race_class": "4",
                        "surface": "TURF",
                        "course": '"A" Course',
                        "horse_id": f"H{runner}",
                        "horse_name": f"Horse {runner}",
                        "jockey": f"J{runner % 4}",
                        "trainer": f"T{runner % 3}",
                        "weight": 120 + runner,
                        "draw": runner + 1,
                        "finish_position": finish,
                        "field_size": 8,
                        "won": int(finish == 1),
                        "placed": int(finish <= 3),
                    }
                )
        model, builder, _ = train_racing_model(pd.DataFrame(rows))
        runners = [
            {
                "horse_id": f"H{runner}",
                "horse_name": f"Horse {runner}",
                "number": runner + 1,
                "last_six": "1/2/3/4",
                "weight": 120 + runner,
                "jockey": f"J{runner % 4}",
                "draw": runner + 1,
                "trainer": f"T{runner % 3}",
            }
            for runner in range(8)
        ]
        predictions = build_predictions(
            model,
            builder,
            [
                {
                    "race_id": "HK:2026-01-01:ST:1",
                    "date": "2026-01-01",
                    "start_time": "2026-01-01T13:00:00+08:00",
                    "venue": "Sha Tin",
                    "venue_code": "ST",
                    "race_number": 1,
                    "race_name": "Test",
                    "distance": 1200,
                    "surface": "TURF",
                    "course": '"A" Course',
                    "going": "GOOD",
                    "race_class": "4",
                    "runners": runners,
                }
            ],
        )
        self.assertAlmostEqual(
            sum(
                runner["winProbability"]
                for runner in predictions[0]["runners"]
            ),
            1,
            places=3,
        )
        self.assertAlmostEqual(
            sum(
                runner["placeProbability"]
                for runner in predictions[0]["runners"]
            ),
            3,
            places=3,
        )


class RacingMarketTests(unittest.TestCase):
    def test_market_probabilities_and_blend_are_normalised_by_race(self) -> None:
        frame = add_market_probabilities(
            pd.DataFrame(
                [
                    {
                        "race_id": "R1",
                        "odds": 2.5,
                        "model_probability": 0.6,
                        "won": 1,
                    },
                    {
                        "race_id": "R1",
                        "odds": 4.0,
                        "model_probability": 0.4,
                        "won": 0,
                    },
                ]
            )
        )
        probability = blend_probabilities(frame, 0, 1)
        self.assertAlmostEqual(frame["market_probability"].sum(), 1)
        self.assertAlmostEqual(probability.sum(), 1)
        pd.testing.assert_series_equal(
            probability.reset_index(drop=True),
            frame["market_probability"].reset_index(drop=True),
            check_names=False,
        )

    def test_market_calibration_lower_bound_cannot_inflate_probability(self) -> None:
        rows = []
        for index in range(20):
            rows.extend(
                [
                    {
                        "date": f"2024-01-{index + 1:02d}",
                        "race_id": f"R{index}",
                        "race_number": 1,
                        "odds": 3.0,
                        "model_probability": 0.6,
                        "won": index % 3 == 0,
                    },
                    {
                        "date": f"2024-01-{index + 1:02d}",
                        "race_id": f"R{index}",
                        "race_number": 1,
                        "odds": 2.0,
                        "model_probability": 0.4,
                        "won": index % 3 != 0,
                    },
                ]
            )
        frame = add_market_probabilities(pd.DataFrame(rows))
        blend = MarketBlend(model_weight=0.2, temperature=1, log_loss=0)
        probability = blend_probabilities(frame, 0.2, 1)
        multipliers = calibration_lower_multipliers(
            frame,
            probability,
            iterations=50,
        )
        conservative = apply_conservative_probabilities(
            frame,
            blend,
            multipliers,
        )
        self.assertTrue(all(0 <= value <= 1 for value in multipliers.values()))
        self.assertTrue(
            (
                conservative["conservative_probability"]
                <= conservative["calibrated_probability"]
            ).all()
        )

    def test_trade_policy_requires_positive_meeting_bootstrap_lower_roi(
        self,
    ) -> None:
        rows = []
        for index in range(40):
            rows.extend(
                [
                    {
                        "date": f"2024-{index // 28 + 1:02d}-{index % 28 + 1:02d}",
                        "race_id": f"R{index}",
                        "race_number": 1,
                        "odds": 3.0,
                        "won": True,
                        "conservative_ev": 0.2,
                    },
                    {
                        "date": f"2024-{index // 28 + 1:02d}-{index % 28 + 1:02d}",
                        "race_id": f"R{index}",
                        "race_number": 1,
                        "odds": 4.0,
                        "won": False,
                        "conservative_ev": -0.1,
                    },
                ]
            )
        policy = select_trade_policy(
            pd.DataFrame(rows),
            bootstrap_iterations=50,
        )
        self.assertTrue(policy.trade_enabled)
        self.assertGreater(policy.bootstrap_lower_roi, 0)


class FootballMarketTests(unittest.TestCase):
    def test_two_way_market_probabilities_remove_overround(self) -> None:
        frame = add_two_way_market_probabilities(
            pd.DataFrame(
                [
                    {
                        "over_odds": 1.9,
                        "under_odds": 1.9,
                    }
                ]
            )
        )
        self.assertAlmostEqual(frame.loc[0, "market_over_probability"], 0.5)
        self.assertAlmostEqual(frame.loc[0, "market_under_probability"], 0.5)
        self.assertGreater(frame.loc[0, "market_overround"], 1)
        invalid = add_two_way_market_probabilities(
            pd.DataFrame([{"over_odds": 1.0, "under_odds": 2.0}])
        )
        self.assertTrue(pd.isna(invalid.loc[0, "market_over_probability"]))

    def test_ten_minute_stage_cannot_see_later_snapshot(self) -> None:
        snapshots = select_pre_match_snapshots(
            pd.DataFrame(
                [
                    {
                        "match_id": "M1",
                        "line": 9.5,
                        "captured_at": "2026-01-01T11:40:00Z",
                        "market_time": "2026-01-01T12:00:00Z",
                        "in_play": False,
                    },
                    {
                        "match_id": "M1",
                        "line": 9.5,
                        "captured_at": "2026-01-01T11:55:00Z",
                        "market_time": "2026-01-01T12:00:00Z",
                        "in_play": False,
                    },
                ]
            ),
            lead_minutes=10,
        )
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(
            snapshots.loc[0, "captured_at"].isoformat(),
            "2026-01-01T11:40:00+00:00",
        )

    def test_conservative_probability_and_limit_price(self) -> None:
        frame = add_two_way_market_probabilities(
            pd.DataFrame(
                [
                    {
                        "match_id": "E0:2026-01-01:A:B",
                        "date": "2026-01-01",
                        "line": 9.5,
                        "over_odds": 2.1,
                        "under_odds": 1.8,
                        "model_over_probability": 0.6,
                        "over_won": True,
                    }
                ]
            )
        )
        blend = FootballMarketBlend(
            model_weight=0.5,
            temperature=1,
            brier_score=0,
        )
        probability = pd.Series([0.6])
        multipliers = football_calibration_lower_multipliers(
            frame,
            probability,
            iterations=50,
        )
        conservative = apply_football_conservative(
            frame,
            blend,
            multipliers,
        )
        self.assertLessEqual(
            conservative.loc[0, "conservative_over_probability"],
            conservative.loc[0, "calibrated_over_probability"],
        )
        self.assertGreater(conservative.loc[0, "minimum_over_odds"], 1)

    def test_positive_synthetic_football_policy_can_pass(self) -> None:
        rows = []
        for index in range(120):
            rows.append(
                {
                    "match_id": f"M{index}",
                    "date": f"2026-{index // 28 + 1:02d}-{index % 28 + 1:02d}",
                    "over_odds": 2.0,
                    "under_odds": 1.9,
                    "over_conservative_ev": 0.2,
                    "under_conservative_ev": -0.1,
                    "over_won": True,
                }
            )
        policy = select_football_trade_policy(
            pd.DataFrame(rows),
            bootstrap_iterations=50,
        )
        self.assertTrue(policy.trade_enabled)
        self.assertGreater(policy.bootstrap_lower_roi, 0)

    def test_over_and_under_can_be_selected(self) -> None:
        selected = football_policy_selections(
            pd.DataFrame(
                [
                    {
                        "match_id": "M1",
                        "date": "2026-01-01",
                        "over_odds": 1.9,
                        "under_odds": 2.1,
                        "over_conservative_ev": -0.1,
                        "under_conservative_ev": 0.2,
                        "over_won": False,
                    },
                    {
                        "match_id": "M2",
                        "date": "2026-01-02",
                        "over_odds": 2.1,
                        "under_odds": 1.9,
                        "over_conservative_ev": 0.2,
                        "under_conservative_ev": -0.1,
                        "over_won": True,
                    },
                ]
            ),
            minimum_conservative_ev=0.05,
        )
        self.assertEqual(set(selected["direction"]), {"over", "under"})

    def test_imports_pre_match_betfair_corner_snapshots(self) -> None:
        lines = [
            json.dumps(
                {
                    "pt": 1760000000000,
                    "mc": [
                        {
                            "id": "1.234",
                            "marketDefinition": {
                                "eventName": "Alpha v Beta",
                                "name": "Over/Under 9.5 Corners",
                                "marketType": "TOTAL_CORNERS",
                                "marketTime": "2026-01-10T15:00:00Z",
                                "inPlay": False,
                                "runners": [
                                    {"id": 1, "name": "Over 9.5"},
                                    {"id": 2, "name": "Under 9.5"},
                                ],
                            },
                            "rc": [
                                {"id": 1, "ltp": 1.95},
                                {"id": 2, "ltp": 2.02},
                            ],
                        }
                    ],
                }
            )
        ]
        snapshots = parse_basic_stream(lines)
        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0].line, 9.5)
        self.assertEqual(snapshots[0].over_odds, 1.95)
        self.assertEqual(snapshots[0].under_odds, 2.02)

    def test_imports_compressed_stream_and_filters_in_play(self) -> None:
        with TemporaryDirectory() as directory:
            path = Path(directory) / "corners.bz2"
            first = {
                "pt": 1760000000000,
                "mc": [
                    {
                        "id": "1.234",
                        "marketDefinition": {
                            "eventName": "Manchester United v Beta",
                            "name": "Over/Under 9.5 Corners",
                            "marketType": "TOTAL_CORNERS",
                            "marketTime": "2026-01-10T15:00:00Z",
                            "inPlay": False,
                            "runners": [
                                {"id": 1, "name": "Over 9.5"},
                                {"id": 2, "name": "Under 9.5"},
                            ],
                        },
                        "rc": [
                            {"id": 1, "ltp": 1.95},
                            {"id": 2, "ltp": 2.02},
                        ],
                    }
                ],
            }
            in_play = {
                "pt": 1768057500000,
                "mc": [
                    {
                        "id": "1.234",
                        "marketDefinition": {"inPlay": True},
                        "rc": [{"id": 1, "ltp": 1.5}],
                    }
                ],
            }
            with bz2.open(path, "wt", encoding="utf-8") as stream:
                stream.write(f"{json.dumps(first)}\n{json.dumps(in_play)}\n")

            snapshots = import_basic_files([path])

            self.assertEqual(len(snapshots), 1)
            self.assertTrue(snapshots[0].is_closing)
            self.assertFalse(snapshots[0].in_play)

    def test_matches_betfair_event_to_football_data_id(self) -> None:
        with TemporaryDirectory() as directory:
            fixtures = Path(directory) / "E0.csv"
            fixtures.write_text(
                "Div,Date,HomeTeam,AwayTeam\n"
                "E0,10/01/2026,Man Utd,Beta\n",
                encoding="utf-8",
            )
            snapshot = parse_basic_stream(
                [
                    json.dumps(
                        {
                            "pt": 1760000000000,
                            "mc": [
                                {
                                    "id": "1.234",
                                    "marketDefinition": {
                                        "eventName": (
                                            "Manchester United v Beta"
                                        ),
                                        "name": "Over/Under 9.5 Corners",
                                        "marketType": "TOTAL_CORNERS",
                                        "marketTime": "2026-01-10T15:00:00Z",
                                        "inPlay": False,
                                        "runners": [
                                            {"id": 1, "name": "Over 9.5"},
                                            {"id": 2, "name": "Under 9.5"},
                                        ],
                                    },
                                    "rc": [
                                        {"id": 1, "ltp": 1.95},
                                        {"id": 2, "ltp": 2.02},
                                    ],
                                }
                            ],
                        }
                    )
                ]
            )[0]

            matched = attach_football_data_match_ids([snapshot], [fixtures])

            self.assertEqual(
                matched[0].match_id,
                "E0:2026-01-10:Man Utd:Beta",
            )

    def test_parses_timestamped_open_meteo_forecast(self) -> None:
        captured = pd.Timestamp("2026-01-01T10:00:00Z").to_pydatetime()
        kickoff = pd.Timestamp("2026-01-01T12:20:00Z").to_pydatetime()
        snapshot = parse_weather_response(
            "E0:2026-01-01:A:B",
            captured,
            kickoff,
            {
                "latitude": 51.5,
                "longitude": -0.1,
                "hourly": {
                    "time": [
                        "2026-01-01T11:00:00+00:00",
                        "2026-01-01T12:00:00+00:00",
                    ],
                    "temperature_2m": [8.0, 8.5],
                    "precipitation_probability": [20, 30],
                    "wind_speed_10m": [10, 12],
                },
            },
        )
        self.assertEqual(snapshot.valid_at, "2026-01-01T12:00:00+00:00")
        self.assertEqual(snapshot.temperature_c, 8.5)


if __name__ == "__main__":
    unittest.main()
