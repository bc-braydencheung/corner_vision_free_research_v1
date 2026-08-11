from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy.stats import nbinom
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression, PoissonRegressor
from sklearn.metrics import mean_absolute_error, mean_poisson_deviance
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


@dataclass
class TargetModel:
    strategy: str
    models: tuple[Pipeline, ...]
    baseline_column: str

    def predict(self, features: pd.DataFrame) -> np.ndarray:
        baseline = features[self.baseline_column].to_numpy(dtype=float)
        if self.strategy == "dynamic":
            return np.clip(baseline, 0.1, 20.0)
        matrix = features.drop(columns=["Date"], errors="ignore")
        if self.strategy == "residual":
            residual = np.mean([model.predict(matrix) for model in self.models], axis=0)
            return np.clip((baseline + 0.75) * np.exp(residual) - 0.75, 0.1, 20.0)
        return np.mean(
            [np.clip(model.predict(matrix), 0.1, 20.0) for model in self.models],
            axis=0,
        )


@dataclass
class ForecastModel:
    candidate: str
    feature_names: tuple[str, ...]
    home_model: TargetModel
    away_model: TargetModel
    total_model: TargetModel
    dispersion: float
    calibration: dict[float, tuple[float, float]]
    interval_offsets: tuple[float, float]
    metrics: dict[str, object]
    out_of_fold: pd.DataFrame

    def predict(self, features: pd.DataFrame) -> tuple[np.ndarray, np.ndarray]:
        matrix = features.loc[:, self.feature_names]
        home = self.home_model.predict(matrix)
        away = self.away_model.predict(matrix)
        total = self.total_model.predict(matrix)
        scale = total / np.clip(home + away, 0.1, None)
        return np.clip(home * scale, 0.1, 20.0), np.clip(away * scale, 0.1, 20.0)

    def _calibration_for_line(self, line: float) -> tuple[float, float]:
        lines = sorted(self.calibration)
        if not lines:
            return 0.0, 1.0
        if line <= lines[0]:
            return self.calibration[lines[0]]
        if line >= lines[-1]:
            return self.calibration[lines[-1]]
        upper_index = next(index for index, value in enumerate(lines) if value >= line)
        lower_line = lines[upper_index - 1]
        upper_line = lines[upper_index]
        ratio = (line - lower_line) / (upper_line - lower_line)
        lower = self.calibration[lower_line]
        upper = self.calibration[upper_line]
        return (
            lower[0] + ratio * (upper[0] - lower[0]),
            lower[1] + ratio * (upper[1] - lower[1]),
        )

    def _calibrated_survival(self, mean: float, line: float) -> float:
        raw = over_probability(mean, line, self.dispersion)
        intercept, slope = self._calibration_for_line(line)
        logit = np.log(np.clip(raw, 0.001, 0.999) / np.clip(1.0 - raw, 0.001, 0.999))
        return float(1.0 / (1.0 + np.exp(-(intercept + slope * logit))))

    def total_distribution(self, mean: float, max_count: int = 30) -> list[float]:
        survivals = [1.0]
        for count in range(1, max_count + 1):
            calibrated = self._calibrated_survival(mean, count - 0.5)
            survivals.append(min(survivals[-1], calibrated))
        distribution = [
            max(survivals[count] - survivals[count + 1], 0.0)
            for count in range(max_count)
        ]
        distribution.append(max(survivals[max_count], 0.0))
        total = sum(distribution)
        return [value / total for value in distribution]

    def over_probability(self, mean: float, line: float) -> float:
        distribution = self.total_distribution(mean)
        first_win = int(np.floor(line)) + 1
        return float(sum(distribution[first_win:]))

    def prediction_interval(self, mean: float) -> tuple[int, int]:
        lower_offset, upper_offset = self.interval_offsets
        lower = max(int(np.ceil(mean + lower_offset)), 0)
        upper = max(int(np.floor(mean + upper_offset)), lower + 1)
        return lower, upper


def _poisson_pipeline() -> Pipeline:
    return Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            ("scale", StandardScaler()),
            ("model", PoissonRegressor(alpha=0.35, max_iter=1000)),
        ]
    )


def _boosting_pipeline(loss: str = "poisson") -> Pipeline:
    return Pipeline(
        [
            ("imputer", SimpleImputer(strategy="median")),
            (
                "model",
                HistGradientBoostingRegressor(
                    loss=loss,
                    learning_rate=0.045,
                    max_iter=170,
                    max_leaf_nodes=15,
                    min_samples_leaf=30,
                    l2_regularization=2.0,
                    random_state=42,
                ),
            ),
        ]
    )


def over_probability(mean: float, line: float, dispersion: float) -> float:
    alpha = max(dispersion, 0.001)
    size = 1.0 / alpha
    probability = size / (size + max(mean, 0.01))
    return float(nbinom.sf(int(np.floor(line)), size, probability))


def prediction_interval(mean: float, dispersion: float) -> tuple[int, int]:
    alpha = max(dispersion, 0.001)
    size = 1.0 / alpha
    probability = size / (size + max(mean, 0.01))
    return int(nbinom.ppf(0.1, size, probability)), int(nbinom.ppf(0.9, size, probability))


def _time_weights(dates: pd.Series, reference_date: pd.Timestamp) -> np.ndarray:
    ages = (reference_date - pd.to_datetime(dates)).dt.days.clip(lower=0).to_numpy()
    weights = 0.5 ** (ages / (365.25 * 5.0))
    return np.clip(weights, 0.12, 1.0)


def _fit_pipeline(
    model: Pipeline,
    matrix: pd.DataFrame,
    target: pd.Series | np.ndarray,
    weights: np.ndarray,
) -> None:
    model.fit(matrix, target, model__sample_weight=weights)


def _fit_target(
    candidate: str,
    features: pd.DataFrame,
    target: pd.Series,
    dates: pd.Series,
    baseline_column: str,
    reference_date: pd.Timestamp,
) -> TargetModel:
    if candidate == "dynamic":
        return TargetModel(candidate, (), baseline_column)

    matrix = features.drop(columns=["Date"], errors="ignore")
    weights = (
        _time_weights(dates, reference_date)
        if candidate.endswith("_recent")
        else np.ones(len(dates))
    )
    if candidate in {"poisson_all", "poisson_recent"}:
        models = (_poisson_pipeline(),)
    elif candidate in {"boosting_all", "boosting_recent"}:
        models = (_boosting_pipeline(),)
    elif candidate == "ensemble_all":
        models = (_poisson_pipeline(), _boosting_pipeline())
    elif candidate == "residual_recent":
        models = (_boosting_pipeline(loss="squared_error"),)
        baseline = features[baseline_column].to_numpy(dtype=float)
        residual_target = np.log((target.to_numpy(dtype=float) + 0.75) / (baseline + 0.75))
        for model in models:
            _fit_pipeline(model, matrix, residual_target, weights)
        return TargetModel("residual", models, baseline_column)
    else:
        raise ValueError(f"Unknown candidate: {candidate}")

    for model in models:
        _fit_pipeline(model, matrix, target, weights)
    return TargetModel("direct", models, baseline_column)


def _candidate_predictions(
    train: pd.DataFrame,
    validation: pd.DataFrame,
    feature_names: list[str],
    candidate: str,
) -> tuple[np.ndarray, np.ndarray]:
    train_x = train.loc[:, feature_names]
    validation_x = validation.loc[:, feature_names]
    reference_date = pd.Timestamp(validation["Date"].min())
    home_model = _fit_target(
        candidate,
        train_x,
        train["HomeCorners"],
        train["Date"],
        "baseline_home_corners",
        reference_date,
    )
    away_model = _fit_target(
        candidate,
        train_x,
        train["AwayCorners"],
        train["Date"],
        "baseline_away_corners",
        reference_date,
    )
    total_model = _fit_target(
        candidate,
        train_x,
        train["TotalCorners"],
        train["Date"],
        "baseline_total_corners",
        reference_date,
    )
    home = home_model.predict(validation_x)
    away = away_model.predict(validation_x)
    total = total_model.predict(validation_x)
    scale = total / np.clip(home + away, 0.1, None)
    return np.clip(home * scale, 0.1, 20.0), np.clip(away * scale, 0.1, 20.0)


def _dispersion(actual: np.ndarray, predicted: np.ndarray) -> float:
    squared_residual = np.mean((actual - predicted) ** 2)
    mean_prediction = max(float(np.mean(predicted)), 0.1)
    return max((squared_residual - mean_prediction) / (mean_prediction**2), 0.02)


def _calibration_error(probabilities: np.ndarray, actual: np.ndarray) -> float:
    bins = np.linspace(0.0, 1.0, 6)
    total = len(actual)
    error = 0.0
    for lower, upper in zip(bins[:-1], bins[1:]):
        mask = (probabilities >= lower) & (
            probabilities <= upper if upper == 1.0 else probabilities < upper
        )
        if mask.any():
            error += mask.mean() * abs(probabilities[mask].mean() - actual[mask].mean())
    return float(error if total else 0.0)


def _fit_calibration(
    actual_total: np.ndarray,
    predicted_total: np.ndarray,
    dispersion: float,
    line: float,
) -> tuple[float, float]:
    raw = np.array(
        [over_probability(value, line, dispersion) for value in predicted_total]
    )
    logits = np.log(np.clip(raw, 0.001, 0.999) / np.clip(1.0 - raw, 0.001, 0.999))
    actual = (actual_total > line).astype(int)
    calibration = LogisticRegression(C=0.5, max_iter=1000)
    calibration.fit(logits.reshape(-1, 1), actual)
    return float(calibration.intercept_[0]), float(calibration.coef_[0, 0])


def _apply_calibration(
    predicted_total: np.ndarray,
    dispersion: float,
    line: float,
    coefficients: tuple[float, float],
) -> np.ndarray:
    raw = np.array(
        [over_probability(value, line, dispersion) for value in predicted_total]
    )
    logits = np.log(np.clip(raw, 0.001, 0.999) / np.clip(1.0 - raw, 0.001, 0.999))
    intercept, slope = coefficients
    return 1.0 / (1.0 + np.exp(-(intercept + slope * logits)))


def train_walk_forward(feature_frame: pd.DataFrame, feature_names: list[str]) -> ForecastModel:
    seasons = feature_frame["Season"].drop_duplicates().tolist()
    if len(seasons) < 9:
        raise RuntimeError("At least nine seasons are required for nested walk-forward validation.")

    candidates = (
        "dynamic",
        "poisson_all",
        "poisson_recent",
        "boosting_all",
        "boosting_recent",
        "residual_recent",
        "ensemble_all",
    )
    fold_frames: list[pd.DataFrame] = []
    for season_index in range(6, len(seasons)):
        validation_season = seasons[season_index]
        train = feature_frame.loc[feature_frame["Season"].isin(seasons[:season_index])]
        validation = feature_frame.loc[feature_frame["Season"].eq(validation_season)]
        fold = validation[
            [
                "Date",
                "Season",
                "HomeTeam",
                "AwayTeam",
                "HomeCorners",
                "AwayCorners",
                "TotalCorners",
                "home_promoted_flag",
                "away_promoted_flag",
            ]
        ].copy()
        for candidate in candidates:
            home, away = _candidate_predictions(train, validation, feature_names, candidate)
            fold[f"{candidate}_home"] = home
            fold[f"{candidate}_away"] = away
            fold[f"{candidate}_total"] = home + away
        fold_frames.append(fold)

    out_of_fold = pd.concat(fold_frames, ignore_index=True)
    validation_seasons = out_of_fold["Season"].drop_duplicates().tolist()
    locked_seasons = validation_seasons[-2:]
    development = out_of_fold.loc[~out_of_fold["Season"].isin(locked_seasons)]
    holdout = out_of_fold.loc[out_of_fold["Season"].isin(locked_seasons)]
    candidate_scores = {
        candidate: mean_absolute_error(
            development["TotalCorners"],
            development[f"{candidate}_total"],
        )
        for candidate in candidates
    }
    selected = min(candidate_scores, key=candidate_scores.get)

    development_actual = development["TotalCorners"].to_numpy(dtype=float)
    development_predicted = development[f"{selected}_total"].to_numpy(dtype=float)
    evaluation_dispersion = _dispersion(development_actual, development_predicted)
    holdout_actual = holdout["TotalCorners"].to_numpy(dtype=float)
    holdout_predicted = holdout[f"{selected}_total"].to_numpy(dtype=float)
    dynamic_holdout = holdout["dynamic_total"].to_numpy(dtype=float)
    holdout_mae = mean_absolute_error(holdout_actual, holdout_predicted)
    dynamic_mae = mean_absolute_error(holdout_actual, dynamic_holdout)
    promoted_mask = (
        holdout["home_promoted_flag"].to_numpy(dtype=float)
        + holdout["away_promoted_flag"].to_numpy(dtype=float)
    ) > 0
    evaluation_offsets = tuple(
        float(value)
        for value in np.quantile(
            development_actual - development_predicted,
            [0.1, 0.9],
        )
    )
    intervals = np.array(
        [
            (
                max(int(np.ceil(value + evaluation_offsets[0])), 0),
                max(int(np.floor(value + evaluation_offsets[1])), 1),
            )
            for value in holdout_predicted
        ]
    )

    metrics: dict[str, object] = {
        "selectedModel": selected,
        "selectionMethod": (
            "candidate selection excludes latest two seasons; "
            "future shadow results remain the definitive test"
        ),
        "validationMatches": int(len(out_of_fold)),
        "validationSeasons": int(len(validation_seasons)),
        "developmentMatches": int(len(development)),
        "holdoutMatches": int(len(holdout)),
        "holdoutSeasons": locked_seasons,
        "maeTotalCorners": round(float(holdout_mae), 3),
        "maeDevelopment": round(float(candidate_scores[selected]), 3),
        "baselineMaeHoldout": round(float(dynamic_mae), 3),
        "maeSkillVsDynamicPercent": round(
            float(100.0 * (dynamic_mae - holdout_mae) / dynamic_mae),
            2,
        ),
        "withinTwoHoldout": round(float(np.mean(np.abs(holdout_actual - holdout_predicted) <= 2)), 4),
        "interval80CoverageHoldout": round(
            float(
                np.mean(
                    (holdout_actual >= intervals[:, 0])
                    & (holdout_actual <= intervals[:, 1])
                )
            ),
            4,
        ),
        "poissonDevianceHome": round(
            float(
                mean_poisson_deviance(
                    holdout["HomeCorners"],
                    np.clip(holdout[f"{selected}_home"], 0.01, None),
                )
            ),
            3,
        ),
        "poissonDevianceAway": round(
            float(
                mean_poisson_deviance(
                    holdout["AwayCorners"],
                    np.clip(holdout[f"{selected}_away"], 0.01, None),
                )
            ),
            3,
        ),
        "candidateMaeDevelopment": {
            candidate: round(float(score), 4)
            for candidate, score in candidate_scores.items()
        },
    }
    if promoted_mask.any():
        metrics["promotedHoldoutMatches"] = int(promoted_mask.sum())
        metrics["maePromotedHoldout"] = round(
            float(
                mean_absolute_error(
                    holdout_actual[promoted_mask],
                    holdout_predicted[promoted_mask],
                )
            ),
            3,
        )
        metrics["baselineMaePromotedHoldout"] = round(
            float(
                mean_absolute_error(
                    holdout_actual[promoted_mask],
                    dynamic_holdout[promoted_mask],
                )
            ),
            3,
        )
    for line in (8.5, 9.5, 10.5):
        coefficients = _fit_calibration(
            development_actual,
            development_predicted,
            evaluation_dispersion,
            line,
        )
        probabilities = _apply_calibration(
            holdout_predicted,
            evaluation_dispersion,
            line,
            coefficients,
        )
        actual = (holdout_actual > line).astype(float)
        baseline_probability = float(np.mean(development_actual > line))
        baseline_brier = float(np.mean((baseline_probability - actual) ** 2))
        model_brier = float(np.mean((probabilities - actual) ** 2))
        suffix = str(line).replace(".", "_")
        metrics[f"brierOver{suffix}"] = round(model_brier, 4)
        metrics[f"brierSkillOver{suffix}Percent"] = round(
            100.0 * (baseline_brier - model_brier) / baseline_brier,
            2,
        )
        metrics[f"calibrationErrorOver{suffix}"] = round(
            _calibration_error(probabilities, actual),
            4,
        )

    full_x = feature_frame.loc[:, feature_names]
    reference_date = pd.Timestamp(feature_frame["Date"].max()) + pd.Timedelta(days=1)
    home_model = _fit_target(
        selected,
        full_x,
        feature_frame["HomeCorners"],
        feature_frame["Date"],
        "baseline_home_corners",
        reference_date,
    )
    away_model = _fit_target(
        selected,
        full_x,
        feature_frame["AwayCorners"],
        feature_frame["Date"],
        "baseline_away_corners",
        reference_date,
    )
    total_model = _fit_target(
        selected,
        full_x,
        feature_frame["TotalCorners"],
        feature_frame["Date"],
        "baseline_total_corners",
        reference_date,
    )

    selected_columns = [
        "Date",
        "Season",
        "HomeTeam",
        "AwayTeam",
        "HomeCorners",
        "AwayCorners",
        "TotalCorners",
        f"{selected}_home",
        f"{selected}_away",
        f"{selected}_total",
    ]
    selected_oof = out_of_fold.loc[:, selected_columns].rename(
        columns={
            f"{selected}_home": "PredictedHomeCorners",
            f"{selected}_away": "PredictedAwayCorners",
            f"{selected}_total": "PredictedTotalCorners",
        }
    )
    production_dispersion = _dispersion(
        selected_oof["TotalCorners"].to_numpy(dtype=float),
        selected_oof["PredictedTotalCorners"].to_numpy(dtype=float),
    )
    production_calibration = {
        line: _fit_calibration(
            selected_oof["TotalCorners"].to_numpy(dtype=float),
            selected_oof["PredictedTotalCorners"].to_numpy(dtype=float),
            production_dispersion,
            line,
        )
        for line in (7.5, 8.5, 9.5, 10.5, 11.5, 12.5)
    }
    production_offsets = tuple(
        float(value)
        for value in np.quantile(
            selected_oof["TotalCorners"].to_numpy(dtype=float)
            - selected_oof["PredictedTotalCorners"].to_numpy(dtype=float),
            [0.1, 0.9],
        )
    )
    return ForecastModel(
        candidate=selected,
        feature_names=tuple(feature_names),
        home_model=home_model,
        away_model=away_model,
        total_model=total_model,
        dispersion=float(production_dispersion),
        calibration=production_calibration,
        interval_offsets=production_offsets,
        metrics=metrics,
        out_of_fold=selected_oof,
    )
