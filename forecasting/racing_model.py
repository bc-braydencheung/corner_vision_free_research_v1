from __future__ import annotations

import math
import re
from collections import defaultdict, deque
from dataclasses import dataclass, field
from datetime import date

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import brier_score_loss, log_loss

FEATURE_COLUMNS = (
    "weight_norm",
    "draw_norm",
    "distance_km",
    "venue_hv",
    "surface_awt",
    "class_number",
    "horse_starts_log",
    "horse_win_rate",
    "horse_place_rate",
    "horse_finish_score",
    "horse_distance_rate",
    "days_since_last_log",
    "jockey_win_rate",
    "jockey_place_rate",
    "trainer_win_rate",
    "trainer_place_rate",
    "recent_form_score",
)


def _rate(successes: float, starts: int, prior: float, strength: float) -> float:
    return (successes + prior * strength) / (starts + strength)


def _class_number(value: object) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 2.5


@dataclass
class EntityState:
    starts: int = 0
    wins: int = 0
    places: int = 0
    finish_total: float = 0.0
    last_date: date | None = None
    recent: deque[float] = field(default_factory=lambda: deque(maxlen=6))
    distance_starts: dict[int, int] = field(default_factory=lambda: defaultdict(int))
    distance_wins: dict[int, int] = field(default_factory=lambda: defaultdict(int))

    def finish_score(self) -> float:
        return self.finish_total / self.starts if self.starts else 0.5

    def recent_score(self) -> float:
        return sum(self.recent) / len(self.recent) if self.recent else self.finish_score()


class RacingFeatureBuilder:
    def __init__(self) -> None:
        self.horses: dict[str, EntityState] = defaultdict(EntityState)
        self.jockeys: dict[str, EntityState] = defaultdict(EntityState)
        self.trainers: dict[str, EntityState] = defaultdict(EntityState)

    def _features(
        self,
        row: dict[str, object],
        field_size: int,
        current_date: date,
    ) -> dict[str, float]:
        horse = self.horses[str(row["horse_id"])]
        jockey = self.jockeys[str(row["jockey"])]
        trainer = self.trainers[str(row["trainer"])]
        distance = int(float(row.get("distance", 0) or 0))
        band = int(round(distance / 200))
        distance_starts = horse.distance_starts.get(band, 0)
        distance_wins = horse.distance_wins.get(band, 0)
        last_days = (
            max((current_date - horse.last_date).days, 0)
            if horse.last_date is not None
            else 90
        )
        last_six = str(row.get("last_six", ""))
        parsed_form = [
            max(1.0 - (int(value) - 1) / max(field_size - 1, 1), 0.0)
            for value in re.findall(r"\d+", last_six)
        ]
        recent_score = (
            sum(parsed_form) / len(parsed_form) if parsed_form else horse.recent_score()
        )
        return {
            "weight_norm": (float(row.get("weight") or 126) - 126) / 10,
            "draw_norm": (float(row.get("draw") or (field_size + 1) / 2) - 1)
            / max(field_size - 1, 1),
            "distance_km": distance / 1000,
            "venue_hv": float(str(row.get("venue_code", "")) == "HV"),
            "surface_awt": float(str(row.get("surface", "")) == "AWT"),
            "class_number": _class_number(row.get("race_class")),
            "horse_starts_log": math.log1p(horse.starts),
            "horse_win_rate": _rate(horse.wins, horse.starts, 0.08, 12),
            "horse_place_rate": _rate(horse.places, horse.starts, 0.25, 12),
            "horse_finish_score": horse.finish_score(),
            "horse_distance_rate": _rate(distance_wins, distance_starts, 0.08, 8),
            "days_since_last_log": math.log1p(last_days) / math.log(181),
            "jockey_win_rate": _rate(jockey.wins, jockey.starts, 0.08, 30),
            "jockey_place_rate": _rate(jockey.places, jockey.starts, 0.25, 30),
            "trainer_win_rate": _rate(trainer.wins, trainer.starts, 0.08, 30),
            "trainer_place_rate": _rate(trainer.places, trainer.starts, 0.25, 30),
            "recent_form_score": recent_score,
        }

    @staticmethod
    def _update(state: EntityState, won: int, placed: int, score: float, when: date) -> None:
        state.starts += 1
        state.wins += won
        state.places += placed
        state.finish_total += score
        state.recent.append(score)
        state.last_date = when

    def fit_transform(self, history: pd.DataFrame) -> pd.DataFrame:
        records: list[dict[str, object]] = []
        ordered = history.sort_values(["date", "race_id", "horse_id"])
        for _, race in ordered.groupby("race_id", sort=False):
            when = pd.Timestamp(race.iloc[0]["date"]).date()
            field_size = int(race.iloc[0]["field_size"])
            pending: list[tuple[dict[str, object], dict[str, float]]] = []
            for raw in race.to_dict("records"):
                features = self._features(raw, field_size, when)
                records.append({**raw, **features})
                pending.append((raw, features))
            for raw, _ in pending:
                finish = int(raw["finish_position"])
                score = max(1.0 - (finish - 1) / max(field_size - 1, 1), 0.0)
                won = int(raw["won"])
                placed = int(raw["placed"])
                horse = self.horses[str(raw["horse_id"])]
                self._update(horse, won, placed, score, when)
                band = int(round(int(float(raw.get("distance", 0) or 0)) / 200))
                horse.distance_starts[band] += 1
                horse.distance_wins[band] += won
                self._update(self.jockeys[str(raw["jockey"])], won, placed, score, when)
                self._update(self.trainers[str(raw["trainer"])], won, placed, score, when)
        return pd.DataFrame(records)

    def transform_upcoming(self, races: list[dict[str, object]]) -> pd.DataFrame:
        records: list[dict[str, object]] = []
        for race in races:
            when = pd.Timestamp(race["date"]).date()
            runners = list(race["runners"])
            field_size = len(runners)
            for runner in runners:
                raw = {
                    **runner,
                    "race_id": race["race_id"],
                    "date": race["date"],
                    "start_time": race["start_time"],
                    "venue": race["venue"],
                    "venue_code": race["venue_code"],
                    "race_number": race["race_number"],
                    "race_name": race["race_name"],
                    "distance": race["distance"],
                    "surface": race["surface"],
                    "course": race["course"],
                    "going": race["going"],
                    "race_class": race["race_class"],
                    "field_size": field_size,
                }
                records.append({**raw, **self._features(raw, field_size, when)})
        return pd.DataFrame(records)


def _normalise_by_race(
    values: np.ndarray,
    race_ids: pd.Series,
    expected_sum: pd.Series | float = 1.0,
) -> np.ndarray:
    output = np.zeros(len(values), dtype=float)
    race_array = race_ids.to_numpy()
    for race_id in pd.unique(race_ids):
        mask = race_array == race_id
        raw = np.clip(values[mask], 1e-6, None)
        target = (
            float(expected_sum.loc[race_ids.index[mask][0]])
            if isinstance(expected_sum, pd.Series)
            else float(expected_sum)
        )
        probabilities = raw / raw.sum() * target
        for _ in range(5):
            over = probabilities > 0.98
            if not over.any():
                break
            excess = float((probabilities[over] - 0.98).sum())
            probabilities[over] = 0.98
            under = ~over
            if under.any():
                probabilities[under] += excess * probabilities[under] / probabilities[under].sum()
        output[mask] = probabilities
    return output


def _race_log_loss(target: pd.Series, probabilities: np.ndarray) -> float:
    winners = target.to_numpy(dtype=bool)
    return float(-np.log(np.clip(probabilities[winners], 1e-8, 1)).mean())


def _baseline_probabilities(frame: pd.DataFrame) -> np.ndarray:
    score = (
        1.6 * frame["horse_win_rate"]
        + 0.8 * frame["horse_finish_score"]
        + 0.55 * frame["jockey_win_rate"]
        + 0.55 * frame["trainer_win_rate"]
        + 0.35 * frame["recent_form_score"]
        - 0.12 * frame["weight_norm"]
    )
    return _normalise_by_race(np.exp(score.to_numpy()), frame["race_id"])


@dataclass
class RacingModel:
    win_model: HistGradientBoostingClassifier
    place_model: HistGradientBoostingClassifier
    selected_candidate: str
    selected_place_candidate: str
    metrics: dict[str, float | int | str]

    def predict(self, frame: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
        features = frame.loc[:, FEATURE_COLUMNS].fillna(0.0)
        if self.selected_candidate == "boosting":
            raw_win = self.win_model.predict_proba(features)[:, 1]
        else:
            raw_win = _baseline_probabilities(frame)
        win = _normalise_by_race(raw_win, frame["race_id"])
        raw_place = (
            self.place_model.predict_proba(features)[:, 1]
            if self.selected_place_candidate == "boosting"
            else frame["horse_place_rate"].to_numpy()
        )
        slots = frame["field_size"].map(
            lambda size: 3.0 if size >= 7 else 2.0 if size >= 4 else 0.0
        )
        place = _normalise_by_race(raw_place, frame["race_id"], slots)
        return win, place


def train_racing_model(
    history: pd.DataFrame,
) -> tuple[RacingModel, RacingFeatureBuilder, pd.DataFrame]:
    if len(history) < 500:
        raise ValueError("At least 500 historical runner records are required.")
    builder = RacingFeatureBuilder()
    frame = builder.fit_transform(history)
    race_dates = (
        frame[["race_id", "date"]]
        .drop_duplicates()
        .sort_values("date")
        .reset_index(drop=True)
    )
    validation_split = max(int(len(race_dates) * 0.7), 1)
    holdout_split = max(int(len(race_dates) * 0.85), validation_split + 1)
    validation_races = set(
        race_dates.iloc[validation_split:holdout_split]["race_id"]
    )
    holdout_races = set(race_dates.iloc[holdout_split:]["race_id"])
    development = frame.loc[
        ~frame["race_id"].isin(validation_races | holdout_races)
    ]
    pre_holdout = frame.loc[~frame["race_id"].isin(holdout_races)]
    validation = frame.loc[frame["race_id"].isin(validation_races)]
    holdout = frame.loc[frame["race_id"].isin(holdout_races)]
    if validation["won"].sum() < 15 or holdout["won"].sum() < 15:
        raise ValueError("Historical data does not contain a sufficient date holdout.")
    win_model = _win_classifier()
    development_place_model = _place_classifier()
    train_x = development.loc[:, FEATURE_COLUMNS].fillna(0.0)
    win_model.fit(train_x, development["won"])
    development_place_model.fit(train_x, development["placed"])
    validation_x = validation.loc[:, FEATURE_COLUMNS].fillna(0.0)
    validation_boosting = _normalise_by_race(
        win_model.predict_proba(validation_x)[:, 1],
        validation["race_id"],
    )
    validation_baseline = _baseline_probabilities(validation)
    validation_slots = validation["field_size"].map(
        lambda size: 3.0 if size >= 7 else 2.0 if size >= 4 else 0.0
    )
    validation_place = _normalise_by_race(
        development_place_model.predict_proba(validation_x)[:, 1],
        validation["race_id"],
        validation_slots,
    )
    validation_place_baseline = _normalise_by_race(
        validation["horse_place_rate"].to_numpy(),
        validation["race_id"],
        validation_slots,
    )
    validation_selected = (
        "boosting"
        if _race_log_loss(validation["won"], validation_boosting)
        < _race_log_loss(validation["won"], validation_baseline)
        else "dynamic"
    )
    validation_selected_place = (
        "boosting"
        if brier_score_loss(
            validation["placed"],
            np.clip(validation_place, 0, 1),
        )
        < brier_score_loss(
            validation["placed"],
            np.clip(validation_place_baseline, 0, 1),
        )
        else "dynamic"
    )
    win_model = _win_classifier()
    place_model = _place_classifier()
    pre_holdout_x = pre_holdout.loc[:, FEATURE_COLUMNS].fillna(0.0)
    win_model.fit(pre_holdout_x, pre_holdout["won"])
    place_model.fit(pre_holdout_x, pre_holdout["placed"])
    holdout_x = holdout.loc[:, FEATURE_COLUMNS].fillna(0.0)
    boosting = _normalise_by_race(
        win_model.predict_proba(holdout_x)[:, 1],
        holdout["race_id"],
    )
    baseline = _baseline_probabilities(holdout)
    boosting_loss = _race_log_loss(holdout["won"], boosting)
    baseline_loss = _race_log_loss(holdout["won"], baseline)
    selected = (
        "boosting"
        if validation_selected == "boosting" and boosting_loss < baseline_loss
        else "dynamic"
    )
    selected_probabilities = boosting if selected == "boosting" else baseline
    raw_place = place_model.predict_proba(holdout_x)[:, 1]
    slots = holdout["field_size"].map(
        lambda size: 3.0 if size >= 7 else 2.0 if size >= 4 else 0.0
    )
    place_probabilities = _normalise_by_race(raw_place, holdout["race_id"], slots)
    baseline_place_probabilities = _normalise_by_race(
        holdout["horse_place_rate"].to_numpy(),
        holdout["race_id"],
        slots,
    )
    place_brier = float(
        brier_score_loss(
            holdout["placed"],
            np.clip(place_probabilities, 0, 1),
        )
    )
    baseline_place_brier = float(
        brier_score_loss(
            holdout["placed"],
            np.clip(baseline_place_probabilities, 0, 1),
        )
    )
    selected_place = (
        "boosting"
        if validation_selected_place == "boosting"
        and place_brier < baseline_place_brier
        else "dynamic"
    )
    metrics: dict[str, float | int | str] = {
        "selectedCandidate": selected,
        "selectedPlaceCandidate": selected_place,
        "validationSelectedPlaceCandidate": validation_selected_place,
        "validationSelectedCandidate": validation_selected,
        "deploymentStatus": (
            "boosting-passed-holdout"
            if selected == "boosting"
            else "dynamic-baseline-retained"
        ),
        "trainingRaces": int(pre_holdout["race_id"].nunique()),
        "validationRaces": int(validation["race_id"].nunique()),
        "holdoutRaces": int(holdout["race_id"].nunique()),
        "trainingRunners": int(len(pre_holdout)),
        "holdoutRunners": int(len(holdout)),
        "winLogLoss": round(_race_log_loss(holdout["won"], selected_probabilities), 4),
        "baselineWinLogLoss": round(baseline_loss, 4),
        "winLogLossSkillPercent": round(
            100 * (baseline_loss - _race_log_loss(holdout["won"], selected_probabilities))
            / baseline_loss,
            2,
        ),
        "winBrier": round(
            float(brier_score_loss(holdout["won"], selected_probabilities)), 4
        ),
        "placeBrier": round(
            place_brier if selected_place == "boosting" else baseline_place_brier,
            4,
        ),
        "baselinePlaceBrier": round(baseline_place_brier, 4),
        "trainedThrough": str(pd.to_datetime(history["date"]).max().date()),
    }
    final_win = _win_classifier().fit(
        frame.loc[:, FEATURE_COLUMNS].fillna(0.0), frame["won"]
    )
    final_place = _place_classifier().fit(
        frame.loc[:, FEATURE_COLUMNS].fillna(0.0), frame["placed"]
    )
    return (
        RacingModel(final_win, final_place, selected, selected_place, metrics),
        builder,
        frame,
    )


def _win_classifier() -> HistGradientBoostingClassifier:
    return HistGradientBoostingClassifier(
        learning_rate=0.055,
        max_iter=140,
        max_leaf_nodes=15,
        l2_regularization=5.0,
        min_samples_leaf=30,
        random_state=42,
    )


def _place_classifier() -> HistGradientBoostingClassifier:
    return HistGradientBoostingClassifier(
        learning_rate=0.05,
        max_iter=140,
        max_leaf_nodes=15,
        l2_regularization=5.0,
        min_samples_leaf=30,
        random_state=43,
    )


def _confidence(
    win_probability: float,
    starts: float,
    skill: float,
    field_size: int,
    baseline_selected: bool,
) -> tuple[str, float]:
    favourite_baseline = 1 / max(field_size, 1)
    edge = max(win_probability - favourite_baseline, 0)
    experience = min(starts / math.log1p(20), 1.0)
    stability = 0.62 if baseline_selected else 0.75 if skill > 0 else 0.42
    score = 0.45 * min(edge / 0.16, 1.0) + 0.3 * experience + 0.25 * stability
    if skill <= 0 and not baseline_selected:
        score = min(score, 0.52)
    if score >= 0.76:
        return "high", score
    if score >= 0.62:
        return "medium", score
    if score >= 0.46:
        return "low", score
    return "avoid", score


def build_predictions(
    model: RacingModel,
    builder: RacingFeatureBuilder,
    races: list[dict[str, object]],
) -> list[dict[str, object]]:
    if not races:
        return []
    frame = builder.transform_upcoming(races)
    if "horse_name_english" not in frame:
        frame["horse_name_english"] = frame["horse_name"]
    if "horse_name_chinese" not in frame:
        frame["horse_name_chinese"] = ""
    win, place = model.predict(frame)
    frame = frame.assign(win_probability=win, place_probability=place)
    skill = float(model.metrics["winLogLossSkillPercent"])
    output: list[dict[str, object]] = []
    for race_id, group in frame.groupby("race_id", sort=False):
        runners: list[dict[str, object]] = []
        for row in group.sort_values("win_probability", ascending=False).itertuples():
            confidence, score = _confidence(
                float(row.win_probability),
                max(
                    float(row.horse_starts_log),
                    math.log1p(len(re.findall(r"\d+", str(row.last_six)))),
                ),
                skill,
                int(row.field_size),
                model.selected_candidate == "dynamic",
            )
            factors = []
            if row.horse_win_rate > 0.11:
                factors.append("馬匹歷史勝出率高於平滑基準")
            if row.recent_form_score > 0.62:
                factors.append("近仗名次走勢較佳")
            if row.jockey_win_rate > 0.1:
                factors.append("騎師歷史勝出率較佳")
            if row.trainer_win_rate > 0.1:
                factors.append("練馬師歷史勝出率較佳")
            if not factors:
                factors.append("模型優勢有限，宜觀察而非模擬買入")
            runners.append(
                {
                    "horseId": str(row.horse_id),
                    "horseName": str(row.horse_name),
                    "horseNameEnglish": str(row.horse_name_english),
                    "horseNameChinese": str(row.horse_name_chinese),
                    "number": int(row.number),
                    "draw": int(row.draw) if not pd.isna(row.draw) else 0,
                    "jockey": str(row.jockey),
                    "trainer": str(row.trainer),
                    "winProbability": round(float(row.win_probability), 4),
                    "placeProbability": round(float(row.place_probability), 4),
                    "fairWinOdds": round(1 / max(float(row.win_probability), 0.01), 2),
                    "fairPlaceOdds": round(
                        1 / max(float(row.place_probability), 0.01), 2
                    ),
                    "confidence": confidence,
                    "confidenceScore": round(score, 2),
                    "recommendation": (
                        "no-prediction" if confidence == "avoid" else "model-view"
                    ),
                    "factors": factors[:2],
                }
            )
        first = group.iloc[0]
        output.append(
            {
                "raceId": str(race_id),
                "date": str(first["date"]),
                "startTime": str(first["start_time"]),
                "venue": str(first["venue"]),
                "raceNumber": int(first["race_number"]),
                "raceName": str(first["race_name"]),
                "distanceMetres": int(first["distance"]),
                "surface": str(first["surface"]),
                "course": str(first["course"]),
                "going": str(first["going"]),
                "raceClass": str(first["race_class"]),
                "runners": runners,
            }
        )
    return output
