from __future__ import annotations

import math
from collections import defaultdict
from dataclasses import dataclass, field

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class Observation:
    value: float
    date: pd.Timestamp
    weight: float


@dataclass
class TeamState:
    values: dict[str, list[Observation]] = field(default_factory=lambda: defaultdict(list))
    division_dates: dict[str, list[pd.Timestamp]] = field(
        default_factory=lambda: defaultdict(list)
    )
    last_played: pd.Timestamp | None = None
    elo: float = 1500.0

    def add(
        self,
        key: str,
        value: float,
        match_date: pd.Timestamp,
        weight: float,
    ) -> None:
        self.values[key].append(Observation(value, match_date, weight))

    def bayesian_mean(
        self,
        key: str,
        match_date: pd.Timestamp,
        prior: float,
        prior_weight: float = 4.0,
        half_life_days: float = 210.0,
        limit: int = 30,
    ) -> float:
        observations = self.values[key][-limit:]
        if not observations:
            return prior
        weighted_sum = prior * prior_weight
        total_weight = prior_weight
        for observation in observations:
            age = max((match_date - observation.date).days, 0)
            recency = 0.5 ** (age / half_life_days)
            weight = observation.weight * recency
            weighted_sum += observation.value * weight
            total_weight += weight
        return float(weighted_sum / total_weight)

    def window_mean(self, key: str, window: int, default: float) -> float:
        observations = self.values[key][-window:]
        if not observations:
            return default
        recency = np.geomspace(0.45, 1.0, len(observations))
        weights = np.array(
            [
                observation.weight * recency[index]
                for index, observation in enumerate(observations)
            ]
        )
        return float(
            np.average(
                [observation.value for observation in observations],
                weights=weights,
            )
        )

    def recent_games(self, division: str, match_date: pd.Timestamp, days: int = 500) -> int:
        return sum(
            0 <= (match_date - played).days <= days
            for played in self.division_dates[division]
        )

    def weighted_games(
        self,
        match_date: pd.Timestamp,
        target_division: str,
        support_division: str,
    ) -> float:
        top = self.recent_games(target_division, match_date, 900)
        support = self.recent_games(support_division, match_date, 900)
        return float(top + 0.55 * support)


@dataclass
class LeagueState:
    home_corners: list[float] = field(default_factory=list)
    away_corners: list[float] = field(default_factory=list)

    def mean_home(self, window: int = 100) -> float:
        values = self.home_corners[-window:]
        return float(np.mean(values)) if values else 5.5

    def mean_away(self, window: int = 100) -> float:
        values = self.away_corners[-window:]
        return float(np.mean(values)) if values else 4.8

    def mean_total(self, window: int = 100) -> float:
        return self.mean_home(window) + self.mean_away(window)


class FeatureBuilder:
    def __init__(
        self,
        target_division: str = "E0",
        support_division: str = "E1",
    ) -> None:
        self.target_division = target_division
        self.support_division = support_division
        self.teams: dict[str, TeamState] = defaultdict(TeamState)
        self.leagues: dict[str, LeagueState] = defaultdict(LeagueState)
        self.head_to_head: dict[tuple[str, str], list[Observation]] = defaultdict(list)

    def _division(self, row: pd.Series) -> str:
        if "Division" in row.index and pd.notna(row["Division"]):
            return str(row["Division"])
        if "Div" in row.index and pd.notna(row["Div"]):
            return str(row["Div"])
        return self.target_division

    @staticmethod
    def _number(row: pd.Series, names: tuple[str, ...], default: float) -> float:
        for name in names:
            if name in row.index and pd.notna(row[name]):
                return float(row[name])
        return default

    def _market_probabilities(self, row: pd.Series) -> tuple[float, float, float, float]:
        home = self._number(row, ("AvgH", "B365H"), 2.35)
        draw = self._number(row, ("AvgD", "B365D"), 3.35)
        away = self._number(row, ("AvgA", "B365A"), 3.15)
        raw = np.array([1.0 / max(home, 1.01), 1.0 / max(draw, 1.01), 1.0 / max(away, 1.01)])
        probabilities = raw / raw.sum()

        over_odds = self._number(row, ("Avg>2.5", "B365>2.5"), 2.0)
        under_odds = self._number(row, ("Avg<2.5", "B365<2.5"), 2.0)
        over_raw = 1.0 / max(over_odds, 1.01)
        under_raw = 1.0 / max(under_odds, 1.01)
        over_probability = over_raw / (over_raw + under_raw)
        return (
            float(probabilities[0]),
            float(probabilities[1]),
            float(probabilities[2]),
            float(over_probability),
        )

    @staticmethod
    def _rest_days(state: TeamState, match_date: pd.Timestamp) -> float:
        if state.last_played is None:
            return 7.0
        return float(np.clip((match_date - state.last_played).days, 2, 30))

    def _support_share(self, state: TeamState, match_date: pd.Timestamp) -> float:
        top = state.recent_games(self.target_division, match_date, 900)
        support = state.recent_games(self.support_division, match_date, 900)
        denominator = top + support
        return float(support / denominator) if denominator else 0.0

    def _promoted_flag(self, state: TeamState, match_date: pd.Timestamp) -> float:
        top = state.recent_games(self.target_division, match_date, 420)
        support = state.recent_games(self.support_division, match_date, 420)
        return float(support >= 8 and top < 8)

    def _head_to_head_mean(
        self,
        home_name: str,
        away_name: str,
        match_date: pd.Timestamp,
        default: float,
    ) -> float:
        observations = self.head_to_head[(home_name, away_name)][-5:]
        if not observations:
            return default
        weights = [
            observation.weight
            * 0.5 ** (max((match_date - observation.date).days, 0) / 365.0)
            for observation in observations
        ]
        return float(
            np.average(
                [observation.value for observation in observations],
                weights=weights,
            )
        )

    def _features_for(self, row: pd.Series) -> dict[str, float]:
        home_name = str(row["HomeTeam"])
        away_name = str(row["AwayTeam"])
        home = self.teams[home_name]
        away = self.teams[away_name]
        match_date = pd.Timestamp(row["Date"])
        league = self.leagues[self.target_division]
        league_home = league.mean_home()
        league_away = league.mean_away()
        default_for = league.mean_total() / 2
        market_home, market_draw, market_away, market_over = self._market_probabilities(row)
        month_angle = 2 * math.pi * (match_date.month - 1) / 12

        home_attack = home.bayesian_mean("corners_for", match_date, default_for)
        home_defence = home.bayesian_mean("corners_against", match_date, default_for)
        away_attack = away.bayesian_mean("corners_for", match_date, default_for)
        away_defence = away.bayesian_mean("corners_against", match_date, default_for)
        home_venue = home.bayesian_mean("home_corners_for", match_date, league_home)
        away_venue = away.bayesian_mean("away_corners_for", match_date, league_away)
        baseline_home = (
            0.35 * home_attack
            + 0.25 * away_defence
            + 0.20 * home_venue
            + 0.20 * league_home
        )
        baseline_away = (
            0.35 * away_attack
            + 0.25 * home_defence
            + 0.20 * away_venue
            + 0.20 * league_away
        )

        return {
            "baseline_home_corners": baseline_home,
            "baseline_away_corners": baseline_away,
            "baseline_total_corners": baseline_home + baseline_away,
            "home_corner_for_dynamic": home_attack,
            "home_corner_against_dynamic": home_defence,
            "away_corner_for_dynamic": away_attack,
            "away_corner_against_dynamic": away_defence,
            "home_corner_for_5": home.window_mean("corners_for", 5, default_for),
            "home_corner_for_10": home.window_mean("corners_for", 10, default_for),
            "home_corner_against_5": home.window_mean(
                "corners_against", 5, default_for
            ),
            "home_corner_against_10": home.window_mean(
                "corners_against", 10, default_for
            ),
            "away_corner_for_5": away.window_mean("corners_for", 5, default_for),
            "away_corner_for_10": away.window_mean("corners_for", 10, default_for),
            "away_corner_against_5": away.window_mean(
                "corners_against", 5, default_for
            ),
            "away_corner_against_10": away.window_mean(
                "corners_against", 10, default_for
            ),
            "home_shots_for_dynamic": home.bayesian_mean(
                "shots_for", match_date, 13.0, prior_weight=5.0
            ),
            "home_shots_against_dynamic": home.bayesian_mean(
                "shots_against", match_date, 13.0, prior_weight=5.0
            ),
            "away_shots_for_dynamic": away.bayesian_mean(
                "shots_for", match_date, 12.0, prior_weight=5.0
            ),
            "away_shots_against_dynamic": away.bayesian_mean(
                "shots_against", match_date, 13.0, prior_weight=5.0
            ),
            "home_shots_for_5": home.window_mean("shots_for", 5, 13.0),
            "home_shots_against_5": home.window_mean("shots_against", 5, 13.0),
            "away_shots_for_5": away.window_mean("shots_for", 5, 12.0),
            "away_shots_against_5": away.window_mean("shots_against", 5, 13.0),
            "home_sot_for_dynamic": home.bayesian_mean(
                "sot_for", match_date, 4.5, prior_weight=5.0
            ),
            "away_sot_for_dynamic": away.bayesian_mean(
                "sot_for", match_date, 4.2, prior_weight=5.0
            ),
            "home_sot_for_5": home.window_mean("sot_for", 5, 4.5),
            "away_sot_for_5": away.window_mean("sot_for", 5, 4.2),
            "home_goals_for_dynamic": home.bayesian_mean(
                "goals_for", match_date, 1.5, prior_weight=5.0
            ),
            "away_goals_for_dynamic": away.bayesian_mean(
                "goals_for", match_date, 1.2, prior_weight=5.0
            ),
            "home_goals_for_5": home.window_mean("goals_for", 5, 1.5),
            "away_goals_for_5": away.window_mean("goals_for", 5, 1.2),
            "home_venue_corners_dynamic": home_venue,
            "away_venue_corners_dynamic": away_venue,
            "home_venue_corners_10": home.window_mean(
                "home_corners_for", 10, league_home
            ),
            "away_venue_corners_10": away.window_mean(
                "away_corners_for", 10, league_away
            ),
            "home_games_log": math.log1p(
                home.weighted_games(
                    match_date,
                    self.target_division,
                    self.support_division,
                )
            ),
            "away_games_log": math.log1p(
                away.weighted_games(
                    match_date,
                    self.target_division,
                    self.support_division,
                )
            ),
            "home_support_share": self._support_share(home, match_date),
            "away_support_share": self._support_share(away, match_date),
            "home_promoted_flag": self._promoted_flag(home, match_date),
            "away_promoted_flag": self._promoted_flag(away, match_date),
            "home_rest_days": self._rest_days(home, match_date),
            "away_rest_days": self._rest_days(away, match_date),
            "elo_difference": (home.elo + 60.0 - away.elo) / 400.0,
            "h2h_total_dynamic": self._head_to_head_mean(
                home_name,
                away_name,
                match_date,
                league.mean_total(),
            ),
            "league_home_corners_100": league_home,
            "league_away_corners_100": league_away,
            "league_total_corners_20": league.mean_total(20),
            "market_home_probability": market_home,
            "market_draw_probability": market_draw,
            "market_away_probability": market_away,
            "market_over_2_5_probability": market_over,
            "market_strength_gap": abs(market_home - market_away),
            "market_script_volatility": (1.0 - market_draw) * market_over,
            "month_sin": math.sin(month_angle),
            "month_cos": math.cos(month_angle),
        }

    def _update(self, row: pd.Series) -> None:
        division = self._division(row)
        division_weight = 1.0 if division == self.target_division else 0.55
        home_name = str(row["HomeTeam"])
        away_name = str(row["AwayTeam"])
        home = self.teams[home_name]
        away = self.teams[away_name]
        division_league = self.leagues[division]
        target_league = self.leagues[self.target_division]
        match_date = pd.Timestamp(row["Date"])
        home_corners = self._number(row, ("HC",), 0.0)
        away_corners = self._number(row, ("AC",), 0.0)
        home_goals = self._number(row, ("FTHG",), 0.0)
        away_goals = self._number(row, ("FTAG",), 0.0)
        home_shots = self._number(row, ("HS",), 13.0)
        away_shots = self._number(row, ("AS",), 12.0)
        home_sot = self._number(row, ("HST",), 4.5)
        away_sot = self._number(row, ("AST",), 4.2)

        if division == self.target_division:
            corner_scale = 1.0
        else:
            corner_scale = float(
                np.clip(
                    target_league.mean_total() / division_league.mean_total(),
                    0.85,
                    1.15,
                )
            )

        updates = (
            (home, "corners_for", home_corners * corner_scale),
            (home, "corners_against", away_corners * corner_scale),
            (away, "corners_for", away_corners * corner_scale),
            (away, "corners_against", home_corners * corner_scale),
            (home, "home_corners_for", home_corners * corner_scale),
            (away, "away_corners_for", away_corners * corner_scale),
            (home, "shots_for", home_shots),
            (home, "shots_against", away_shots),
            (away, "shots_for", away_shots),
            (away, "shots_against", home_shots),
            (home, "sot_for", home_sot),
            (away, "sot_for", away_sot),
            (home, "goals_for", home_goals),
            (away, "goals_for", away_goals),
        )
        for state, key, value in updates:
            state.add(key, value, match_date, division_weight)

        if (
            not home.division_dates[self.target_division]
            and not home.division_dates[self.support_division]
            and division == self.support_division
        ):
            home.elo = 1425.0
        if (
            not away.division_dates[self.target_division]
            and not away.division_dates[self.support_division]
            and division == self.support_division
        ):
            away.elo = 1425.0
        expected_home = 1.0 / (1.0 + 10 ** ((away.elo - home.elo - 60.0) / 400.0))
        if home_goals > away_goals:
            actual_home = 1.0
        elif home_goals < away_goals:
            actual_home = 0.0
        else:
            actual_home = 0.5
        change = 20.0 * division_weight * (actual_home - expected_home)
        home.elo += change
        away.elo -= change
        home.division_dates[division].append(match_date)
        away.division_dates[division].append(match_date)
        home.last_played = match_date
        away.last_played = match_date
        division_league.home_corners.append(home_corners)
        division_league.away_corners.append(away_corners)
        total_corners = (home_corners + away_corners) * corner_scale
        observation = Observation(total_corners, match_date, division_weight)
        self.head_to_head[(home_name, away_name)].append(observation)
        self.head_to_head[(away_name, home_name)].append(observation)

    def fit_transform_history(
        self,
        history: pd.DataFrame,
        target_division: str | None = None,
    ) -> pd.DataFrame:
        selected_division = target_division or self.target_division
        records: list[dict[str, float | int | str | pd.Timestamp]] = []
        ordered = history.sort_values("Date")
        for _, same_day in ordered.groupby("Date", sort=True):
            pending: list[pd.Series] = []
            for _, row in same_day.iterrows():
                if self._division(row) == selected_division:
                    record: dict[str, float | int | str | pd.Timestamp] = self._features_for(row)
                    record.update(
                        {
                            "Date": pd.Timestamp(row["Date"]),
                            "Season": str(row["Season"]),
                            "HomeTeam": str(row["HomeTeam"]),
                            "AwayTeam": str(row["AwayTeam"]),
                            "HomeCorners": int(row["HC"]),
                            "AwayCorners": int(row["AC"]),
                            "TotalCorners": int(row["HC"]) + int(row["AC"]),
                        }
                    )
                    records.append(record)
                pending.append(row)
            for row in pending:
                self._update(row)
        return pd.DataFrame.from_records(records)

    def transform_fixtures(self, fixtures: pd.DataFrame) -> pd.DataFrame:
        records: list[dict[str, float | str | pd.Timestamp]] = []
        for _, row in fixtures.sort_values("Date").iterrows():
            record: dict[str, float | str | pd.Timestamp] = self._features_for(row)
            record.update(
                {
                    "Date": pd.Timestamp(row["Date"]),
                    "HomeTeam": str(row["HomeTeam"]),
                    "AwayTeam": str(row["AwayTeam"]),
                }
            )
            records.append(record)
        return pd.DataFrame.from_records(records)


META_COLUMNS = {
    "Date",
    "Season",
    "HomeTeam",
    "AwayTeam",
    "HomeCorners",
    "AwayCorners",
    "TotalCorners",
}


def feature_columns(frame: pd.DataFrame) -> list[str]:
    return [column for column in frame.columns if column not in META_COLUMNS]
