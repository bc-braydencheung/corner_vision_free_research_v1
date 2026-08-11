from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class FootballMarketBlend:
    model_weight: float
    temperature: float
    brier_score: float


@dataclass(frozen=True)
class FootballTradePolicy:
    maximum_odds: float
    minimum_conservative_ev: float
    validation_bets: int
    validation_roi: float
    bootstrap_lower_roi: float
    trade_enabled: bool
    reason: str


def select_pre_match_snapshots(
    frame: pd.DataFrame,
    *,
    lead_minutes: int = 10,
) -> pd.DataFrame:
    output = frame.copy()
    output["captured_at"] = pd.to_datetime(
        output["captured_at"],
        utc=True,
        errors="coerce",
    )
    output["market_time"] = pd.to_datetime(
        output["market_time"],
        utc=True,
        errors="coerce",
    )
    in_play = output["in_play"].map(
        lambda value: (
            value
            if isinstance(value, bool)
            else str(value).lower() == "true"
        )
    )
    cutoff = output["market_time"] - pd.to_timedelta(lead_minutes, unit="m")
    output = output.loc[
        output["captured_at"].notna()
        & output["market_time"].notna()
        & ~in_play
        & output["captured_at"].le(cutoff)
    ]
    return (
        output.sort_values("captured_at")
        .groupby(["match_id", "line"], as_index=False)
        .tail(1)
        .reset_index(drop=True)
    )


def add_two_way_market_probabilities(frame: pd.DataFrame) -> pd.DataFrame:
    output = frame.copy()
    valid = (
        output["over_odds"].gt(1)
        & output["over_odds"].le(1000)
        & output["under_odds"].gt(1)
        & output["under_odds"].le(1000)
    )
    raw_over = np.where(valid, 1 / output["over_odds"], np.nan)
    raw_under = np.where(valid, 1 / output["under_odds"], np.nan)
    total = raw_over + raw_under
    output["market_overround"] = total
    output["market_over_probability"] = raw_over / total
    output["market_under_probability"] = raw_under / total
    return output


def blend_over_probability(
    frame: pd.DataFrame,
    model_weight: float,
    temperature: float,
) -> pd.Series:
    model = frame["model_over_probability"].clip(1e-8, 1 - 1e-8)
    market = frame["market_over_probability"].clip(1e-8, 1 - 1e-8)
    model_logit = np.log(model / (1 - model))
    market_logit = np.log(market / (1 - market))
    score = (
        model_weight * model_logit + (1 - model_weight) * market_logit
    ) / temperature
    return 1 / (1 + np.exp(-score))


def select_market_blend(frame: pd.DataFrame) -> FootballMarketBlend:
    valid = frame.dropna(
        subset=["model_over_probability", "market_over_probability", "over_won"]
    )
    if valid.empty:
        raise ValueError("No complete football market rows were available.")
    candidates: list[FootballMarketBlend] = []
    actual = valid["over_won"].astype(float)
    for model_weight in np.linspace(0, 1, 11):
        for temperature in (0.8, 0.9, 1.0, 1.1, 1.2):
            probability = blend_over_probability(
                valid,
                float(model_weight),
                temperature,
            )
            candidates.append(
                FootballMarketBlend(
                    model_weight=float(model_weight),
                    temperature=temperature,
                    brier_score=float(np.mean((probability - actual) ** 2)),
                )
            )
    return min(candidates, key=lambda candidate: candidate.brier_score)


def calibration_lower_multipliers(
    frame: pd.DataFrame,
    over_probability: pd.Series,
    *,
    seed: int = 202607,
    iterations: int = 1000,
) -> dict[str, float]:
    work = frame.assign(over_probability=over_probability)
    dates = work["date"].drop_duplicates().to_numpy()
    rng = np.random.default_rng(seed)
    output: dict[str, float] = {}
    for line in sorted(work["line"].dropna().unique()):
        line_frame = work.loc[work["line"].eq(line)]
        for direction in ("over", "under"):
            if direction == "over":
                line_frame = line_frame.assign(
                    direction_probability=line_frame["over_probability"],
                    direction_won=line_frame["over_won"].astype(float),
                    direction_odds=line_frame["over_odds"],
                )
            else:
                line_frame = line_frame.assign(
                    direction_probability=1 - line_frame["over_probability"],
                    direction_won=1 - line_frame["over_won"].astype(float),
                    direction_odds=line_frame["under_odds"],
                )
            line_frame = line_frame.assign(
                odds_bucket=line_frame["direction_odds"].map(odds_bucket)
            )
            for bucket, bucket_frame in line_frame.groupby("odds_bucket"):
                daily = bucket_frame.groupby("date").agg(
                    wins=("direction_won", "sum"),
                    expected=("direction_probability", "sum"),
                )
                ratios: list[float] = []
                for _ in range(iterations):
                    sampled = rng.choice(dates, size=len(dates), replace=True)
                    sample = daily.reindex(sampled, fill_value=0)
                    expected_total = float(sample["expected"].sum())
                    if expected_total > 0:
                        ratios.append(
                            float(sample["wins"].sum() / expected_total)
                        )
                key = f"{direction}:{float(line):g}:{bucket}"
                output[key] = (
                    max(0.0, min(1.0, float(np.quantile(ratios, 0.1))))
                    if ratios
                    else 0.0
                )
    return output


def odds_bucket(odds: float) -> str:
    if odds < 1.75:
        return "1.01-1.75"
    if odds < 2:
        return "1.75-2.00"
    if odds < 2.5:
        return "2.00-2.50"
    if odds < 3:
        return "2.50-3.00"
    return "3.00+"


def apply_conservative_probabilities(
    frame: pd.DataFrame,
    blend: FootballMarketBlend,
    multipliers: dict[str, float],
    *,
    required_margin: float = 0.05,
) -> pd.DataFrame:
    output = frame.copy()
    output["calibrated_over_probability"] = blend_over_probability(
        output,
        blend.model_weight,
        blend.temperature,
    )
    output["calibrated_under_probability"] = (
        1 - output["calibrated_over_probability"]
    )
    over_multiplier = output["line"].map(
        lambda line: float(line)
    )
    over_multiplier = pd.Series(
        [
            multipliers.get(
                f"over:{line:g}:{odds_bucket(float(odds))}",
                0.0,
            )
            for line, odds in zip(
                over_multiplier,
                output["over_odds"],
                strict=True,
            )
        ],
        index=output.index,
    )
    under_multiplier = pd.Series(
        [
            multipliers.get(
                f"under:{float(line):g}:{odds_bucket(float(odds))}",
                0.0,
            )
            for line, odds in zip(
                output["line"],
                output["under_odds"],
                strict=True,
            )
        ],
        index=output.index,
    )
    output["conservative_over_probability"] = (
        output["calibrated_over_probability"] * over_multiplier
    )
    output["conservative_under_probability"] = (
        output["calibrated_under_probability"] * under_multiplier
    )
    output["over_conservative_ev"] = (
        output["conservative_over_probability"] * output["over_odds"] - 1
    )
    output["under_conservative_ev"] = (
        output["conservative_under_probability"] * output["under_odds"] - 1
    )
    output["minimum_over_odds"] = np.where(
        output["conservative_over_probability"] > 0,
        (1 + required_margin) / output["conservative_over_probability"],
        np.inf,
    )
    output["minimum_under_odds"] = np.where(
        output["conservative_under_probability"] > 0,
        (1 + required_margin) / output["conservative_under_probability"],
        np.inf,
    )
    return output


def policy_selections(
    frame: pd.DataFrame,
    *,
    maximum_odds: float = 10,
    minimum_conservative_ev: float,
) -> pd.DataFrame:
    candidates: list[dict[str, object]] = []
    for _, row in frame.iterrows():
        choices = (
            (
                "over",
                float(row["over_conservative_ev"]),
                float(row["over_odds"]),
                bool(row["over_won"]),
            ),
            (
                "under",
                float(row["under_conservative_ev"]),
                float(row["under_odds"]),
                not bool(row["over_won"]),
            ),
        )
        direction, ev, odds, won = max(choices, key=lambda value: value[1])
        if ev < minimum_conservative_ev or not 1 < odds <= maximum_odds:
            continue
        candidate = row.to_dict()
        candidate.update(
            {
                "direction": direction,
                "conservative_ev": ev,
                "odds": odds,
                "won": won,
            }
        )
        candidates.append(candidate)
    if not candidates:
        return pd.DataFrame()
    return pd.DataFrame(candidates).sort_values(["date", "match_id"])


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
        bets=("match_id", "size"),
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
    minimum_bets: int = 100,
    bootstrap_iterations: int = 1000,
) -> FootballTradePolicy:
    candidates: list[FootballTradePolicy] = []
    for maximum_odds in (3.0, 5.0, 10.0):
        for minimum_ev in (0.0, 0.02, 0.05, 0.08, 0.1, 0.15):
            selected = policy_selections(
                validation,
                maximum_odds=maximum_odds,
                minimum_conservative_ev=minimum_ev,
            )
            if len(selected) < minimum_bets:
                continue
            lower_roi = bootstrap_roi_lower(
                selected,
                seed=int(202607 + maximum_odds * 100 + minimum_ev * 1000),
                iterations=bootstrap_iterations,
            )
            candidates.append(
                FootballTradePolicy(
                    maximum_odds=maximum_odds,
                    minimum_conservative_ev=minimum_ev,
                    validation_bets=len(selected),
                    validation_roi=unit_roi(selected),
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
        return FootballTradePolicy(
            maximum_odds=best.maximum_odds,
            minimum_conservative_ev=best.minimum_conservative_ev,
            validation_bets=best.validation_bets,
            validation_roi=best.validation_roi,
            bootstrap_lower_roi=best.bootstrap_lower_roi,
            trade_enabled=False,
            reason="No policy had a positive 90% match-day bootstrap ROI lower bound.",
        )
    return FootballTradePolicy(
        maximum_odds=0,
        minimum_conservative_ev=0,
        validation_bets=0,
        validation_roi=0,
        bootstrap_lower_roi=-1,
        trade_enabled=False,
        reason="No policy produced enough validation bets.",
    )
