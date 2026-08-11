from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


ODDS_BUCKETS = (1.01, 5.0, 10.0, 20.0, 50.0, 1001.0)


@dataclass(frozen=True)
class MarketBlend:
    model_weight: float
    temperature: float
    log_loss: float


@dataclass(frozen=True)
class MarketTradePolicy:
    maximum_odds: float
    minimum_conservative_ev: float
    validation_bets: int
    validation_roi: float
    bootstrap_lower_roi: float
    trade_enabled: bool
    reason: str


def add_market_probabilities(frame: pd.DataFrame) -> pd.DataFrame:
    output = frame.copy()
    valid = output["odds"].gt(1) & output["odds"].le(1000)
    output["raw_market_probability"] = np.where(
        valid,
        1 / output["odds"],
        0.0,
    )
    totals = output.groupby("race_id")["raw_market_probability"].transform("sum")
    field_sizes = output.groupby("race_id")["race_id"].transform("size")
    output["market_probability"] = np.where(
        totals > 0,
        output["raw_market_probability"] / totals,
        1 / field_sizes,
    )
    return output


def blend_probabilities(
    frame: pd.DataFrame,
    model_weight: float,
    temperature: float,
) -> pd.Series:
    model = frame["model_probability"].clip(1e-8, 1)
    market = frame["market_probability"].clip(1e-8, 1)
    log_score = (
        model_weight * np.log(model)
        + (1 - model_weight) * np.log(market)
    ) / temperature
    score = np.exp(log_score)
    return score / score.groupby(frame["race_id"]).transform("sum")


def winner_log_loss(frame: pd.DataFrame, probability: pd.Series) -> float:
    winners = frame["won"].astype(bool)
    return float(-np.log(probability.loc[winners].clip(1e-9, 1)).mean())


def select_market_blend(frame: pd.DataFrame) -> MarketBlend:
    candidates: list[MarketBlend] = []
    for model_weight in np.linspace(0, 1, 11):
        for temperature in (0.8, 0.9, 1.0, 1.1, 1.2):
            probability = blend_probabilities(
                frame,
                float(model_weight),
                temperature,
            )
            candidates.append(
                MarketBlend(
                    model_weight=float(model_weight),
                    temperature=temperature,
                    log_loss=winner_log_loss(frame, probability),
                )
            )
    return min(candidates, key=lambda candidate: candidate.log_loss)


def odds_buckets(odds: pd.Series) -> pd.Series:
    return pd.cut(
        odds,
        ODDS_BUCKETS,
        labels=False,
        include_lowest=True,
        right=False,
    )


def calibration_lower_multipliers(
    frame: pd.DataFrame,
    probability: pd.Series,
    *,
    seed: int = 202407,
    iterations: int = 1000,
) -> dict[int, float]:
    work = frame.assign(
        calibrated_probability=probability,
        odds_bucket=odds_buckets(frame["odds"]),
    )
    dates = work["date"].drop_duplicates().to_numpy()
    rng = np.random.default_rng(seed)
    output: dict[int, float] = {}
    for bucket in range(len(ODDS_BUCKETS) - 1):
        group = work.loc[work["odds_bucket"] == bucket]
        daily = group.groupby("date").agg(
            wins=("won", "sum"),
            expected=("calibrated_probability", "sum"),
        )
        ratios: list[float] = []
        for _ in range(iterations):
            sampled = rng.choice(dates, size=len(dates), replace=True)
            sample = daily.reindex(sampled, fill_value=0)
            expected = float(sample["expected"].sum())
            if expected > 0:
                ratios.append(float(sample["wins"].sum() / expected))
        output[bucket] = (
            max(0.0, min(1.0, float(np.quantile(ratios, 0.1))))
            if ratios
            else 0.0
        )
    return output


def apply_conservative_probabilities(
    frame: pd.DataFrame,
    blend: MarketBlend,
    multipliers: dict[int, float],
) -> pd.DataFrame:
    output = frame.copy()
    output["calibrated_probability"] = blend_probabilities(
        output,
        blend.model_weight,
        blend.temperature,
    )
    output["odds_bucket"] = odds_buckets(output["odds"])
    output["calibration_multiplier"] = (
        output["odds_bucket"].map(multipliers).fillna(0)
    )
    output["conservative_probability"] = (
        output["calibrated_probability"] * output["calibration_multiplier"]
    )
    output["conservative_ev"] = (
        output["conservative_probability"] * output["odds"] - 1
    )
    return output


def policy_selections(
    frame: pd.DataFrame,
    *,
    maximum_odds: float,
    minimum_conservative_ev: float,
) -> pd.DataFrame:
    eligible = frame.loc[
        frame["odds"].gt(1)
        & frame["odds"].le(maximum_odds)
        & frame["conservative_ev"].ge(minimum_conservative_ev)
    ]
    return (
        eligible.sort_values(
            ["date", "race_number", "conservative_ev"],
            ascending=[True, True, False],
        )
        .drop_duplicates("race_id")
        .copy()
    )


def unit_roi(frame: pd.DataFrame) -> float:
    if frame.empty:
        return 0.0
    returns = np.where(frame["won"], frame["odds"] - 1, -1)
    return float(np.mean(returns))


def bootstrap_roi_lower(
    frame: pd.DataFrame,
    *,
    seed: int,
    iterations: int = 1000,
) -> float:
    if frame.empty:
        return -1.0
    daily = frame.assign(
        net_return=np.where(frame["won"], frame["odds"] - 1, -1)
    ).groupby("date").agg(
        net_return=("net_return", "sum"),
        bets=("race_id", "size"),
    )
    dates = daily.index.to_numpy()
    rng = np.random.default_rng(seed)
    values: list[float] = []
    for _ in range(iterations):
        sample = daily.loc[rng.choice(dates, size=len(dates), replace=True)]
        values.append(float(sample["net_return"].sum() / sample["bets"].sum()))
    return float(np.quantile(values, 0.1))


def select_trade_policy(
    validation: pd.DataFrame,
    *,
    minimum_bets: int = 30,
    bootstrap_iterations: int = 1000,
) -> MarketTradePolicy:
    candidates: list[MarketTradePolicy] = []
    for maximum_odds in (5.0, 8.0, 10.0, 15.0, 20.0, 30.0):
        for minimum_ev in (0.0, 0.02, 0.05, 0.1, 0.15):
            selected = policy_selections(
                validation,
                maximum_odds=maximum_odds,
                minimum_conservative_ev=minimum_ev,
            )
            if len(selected) < minimum_bets:
                continue
            roi = unit_roi(selected)
            lower_roi = bootstrap_roi_lower(
                selected,
                seed=int(maximum_odds * 100 + minimum_ev * 1000),
                iterations=bootstrap_iterations,
            )
            candidates.append(
                MarketTradePolicy(
                    maximum_odds=maximum_odds,
                    minimum_conservative_ev=minimum_ev,
                    validation_bets=len(selected),
                    validation_roi=roi,
                    bootstrap_lower_roi=lower_roi,
                    trade_enabled=lower_roi > 0,
                    reason=(
                        "Validation gate passed."
                        if lower_roi > 0
                        else "Validation ROI lower bound was not positive."
                    ),
                )
            )
    passing = [candidate for candidate in candidates if candidate.trade_enabled]
    if passing:
        return max(passing, key=lambda candidate: candidate.bootstrap_lower_roi)
    if candidates:
        best = max(candidates, key=lambda candidate: candidate.bootstrap_lower_roi)
        return MarketTradePolicy(
            maximum_odds=best.maximum_odds,
            minimum_conservative_ev=best.minimum_conservative_ev,
            validation_bets=best.validation_bets,
            validation_roi=best.validation_roi,
            bootstrap_lower_roi=best.bootstrap_lower_roi,
            trade_enabled=False,
            reason="No policy had a positive 90% meeting-bootstrap ROI lower bound.",
        )
    return MarketTradePolicy(
        maximum_odds=0,
        minimum_conservative_ev=0,
        validation_bets=0,
        validation_roi=0,
        bootstrap_lower_roi=-1,
        trade_enabled=False,
        reason="No policy produced enough validation bets.",
    )
