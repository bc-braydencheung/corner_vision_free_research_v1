from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

from forecasting.data import LEAGUES, DataBundle, LeagueConfig, load_data, season_codes
from forecasting.features import FeatureBuilder, feature_columns
from forecasting.football_market import (
    add_two_way_market_probabilities,
    apply_conservative_probabilities,
    blend_over_probability,
    bootstrap_roi_lower,
    calibration_lower_multipliers,
    odds_bucket,
    policy_selections,
    select_market_blend,
    select_pre_match_snapshots,
    select_trade_policy,
    unit_roi,
)
from forecasting.model import ForecastModel, train_walk_forward
from forecasting.racing import build_racing_payload
from forecasting.team_names import translate_team, translate_team_cn
from forecasting.understat import build_understat_frame, add_xg_features
from forecasting.fbref import build_fbref_frame, add_fbref_features
from forecasting.api_football import build_injury_features
from forecasting.visual_crossing import add_wind_features

MODEL_VERSION = "3.1.0"


def _match_id(league_code: str, row: pd.Series) -> str:
    return (
        f"{league_code}:{pd.Timestamp(row['Date']).date().isoformat()}:"
        f"{row['HomeTeam']}:{row['AwayTeam']}"
    )


def _markets(
    distribution: list[float],
) -> list[dict[str, float]]:
    markets: list[dict[str, float]] = []
    for line in (7.5, 8.5, 9.5, 10.5, 11.5, 12.5):
        first_win = int(np.floor(line)) + 1
        over = float(sum(distribution[first_win:]))
        markets.append(
            {
                "line": line,
                "overProbability": round(over, 4),
                "underProbability": round(1.0 - over, 4),
                "fairOverOdds": round(1.0 / max(over, 0.01), 2),
                "fairUnderOdds": round(1.0 / max(1.0 - over, 0.01), 2),
            }
        )
    return markets


def _confidence(
    expected_total: float,
    distribution: list[float],
    model: ForecastModel,
    row: pd.Series,
) -> tuple[str, float, float, float]:
    over = float(sum(distribution[10:]))
    edge = abs(over - 0.5)
    experience = min(float(row["home_games_log"]), float(row["away_games_log"]))
    promoted = max(float(row["home_promoted_flag"]), float(row["away_promoted_flag"]))
    support_share = max(
        float(row["home_support_share"]),
        float(row["away_support_share"]),
    )
    data_quality = float(np.clip(1.0 - 0.45 * support_share, 0.4, 1.0))
    lower, upper = model.prediction_interval(expected_total)
    interval_quality = float(np.clip(1.0 - max((upper - lower) - 7, 0) / 10, 0.2, 1.0))
    calibration_error = float(model.metrics.get("calibrationErrorOver9_5", 0.08))
    calibration_quality = float(np.clip(1.0 - calibration_error / 0.08, 0.15, 1.0))
    experience_quality = float(np.clip((experience - 1.0) / 2.5, 0.15, 1.0))
    model_stability = (
        0.45 * interval_quality
        + 0.35 * calibration_quality
        + 0.20 * experience_quality
    )
    mae_skill = float(model.metrics.get("maeSkillVsDynamicPercent", 0.0))
    brier_skill = float(model.metrics.get("brierSkillOver9_5Percent", 0.0))
    if mae_skill < 0 or brier_skill < 0:
        model_stability *= 0.65
    direction_quality = float(np.clip(edge / 0.16, 0.1, 1.0))
    score = (
        0.42 * data_quality
        + 0.38 * model_stability
        + 0.20 * direction_quality
    )
    if promoted > 0:
        score = min(score, 0.58)
    if mae_skill < 0 or brier_skill < 0:
        score = min(score, 0.5)
    if edge < 0.06 or score < 0.52:
        return "avoid", score, data_quality, model_stability
    if score >= 0.78 and edge >= 0.14:
        return "high", score, data_quality, model_stability
    if score >= 0.63 and edge >= 0.09:
        return "medium", score, data_quality, model_stability
    return "low", score, data_quality, model_stability


def _factors(row: pd.Series, support_name: str) -> list[str]:
    factors: list[str] = []
    recent_attack = float(row["home_corner_for_dynamic"]) + float(
        row["away_corner_for_dynamic"]
    )
    league_total = float(row["league_total_corners_20"])
    defensive_allowance = float(row["home_corner_against_dynamic"]) + float(
        row["away_corner_against_dynamic"]
    )
    if recent_attack > league_total + 0.8:
        factors.append("兩隊近期製造角球高於聯賽基準")
    elif recent_attack < league_total - 0.8:
        factors.append("兩隊近期製造角球低於聯賽基準")
    if defensive_allowance > league_total + 0.8:
        factors.append("雙方近期容許對手取得較多角球")
    if abs(float(row["elo_difference"])) > 0.45:
        factors.append("實力差距可能造成持續壓迫或追趕形勢")
    if abs(float(row["home_rest_days"]) - float(row["away_rest_days"])) >= 3:
        factors.append("雙方休息日差距明顯")
    if max(float(row["home_promoted_flag"]), float(row["away_promoted_flag"])) > 0:
        factors.append(f"升班隊資料已用{support_name}表現作折算先驗")
    if not factors:
        factors.append("近期角球走勢接近聯賽平均")
    return factors[:3]


def _base_record(
    row: pd.Series,
    expected_home: float,
    expected_away: float,
    model: ForecastModel,
    league: LeagueConfig,
) -> dict[str, object]:
    expected_total = expected_home + expected_away
    distribution = model.total_distribution(expected_total)
    lower, upper = model.prediction_interval(expected_total)
    return {
        "matchId": _match_id(league.code, row),
        "leagueCode": league.code,
        "leagueName": league.name,
        "date": pd.Timestamp(row["Date"]).date().isoformat(),
        "homeTeam": str(row["HomeTeam"]),
        "awayTeam": str(row["AwayTeam"]),
        "homeTeamCn": translate_team_cn(str(row["HomeTeam"])),
        "awayTeamCn": translate_team_cn(str(row["AwayTeam"])),
        "expectedHomeCorners": round(float(expected_home), 2),
        "expectedAwayCorners": round(float(expected_away), 2),
        "expectedTotalCorners": round(float(expected_total), 2),
        "interval80": [lower, upper],
        "totalDistribution": [round(value, 7) for value in distribution],
        "markets": _markets(distribution),
    }


def _forecast_record(
    row: pd.Series,
    expected_home: float,
    expected_away: float,
    model: ForecastModel,
    league: LeagueConfig,
) -> dict[str, object]:
    record = _base_record(row, expected_home, expected_away, model, league)
    distribution = record["totalDistribution"]
    confidence, score, data_quality, model_stability = _confidence(
        float(record["expectedTotalCorners"]),
        distribution,
        model,
        row,
    )
    record.update(
        {
            "mode": "forecast",
            "confidence": confidence,
            "confidenceScore": round(score, 2),
            "recommendation": (
                "no-prediction" if confidence == "avoid" else "model-view"
            ),
            "forecastStage": "T-24h free-data",
            "dataQuality": round(data_quality, 2),
            "modelStability": round(model_stability, 2),
            "factors": _factors(row, league.support_name),
        }
    )
    return record


def _attach_market_decision(
    record: dict[str, object],
    model: ForecastModel,
    market_frame: pd.DataFrame | None,
    trade_policy: dict[str, object],
) -> dict[str, object]:
    record.update(
        {
            "marketAvailable": False,
            "tradeEligible": False,
            "tradeReason": (
                "No bet：目前賽事沒有帶時間戳的實際角球盤，"
                "不能計算研究限價。"
            ),
        }
    )
    if market_frame is None or market_frame.empty:
        return record
    snapshots = select_pre_match_snapshots(market_frame, lead_minutes=10)
    snapshots = snapshots.loc[
        snapshots["match_id"].eq(record["matchId"])
        & snapshots["line"].mod(1).eq(0.5)
    ]
    if snapshots.empty:
        return record
    candidates: list[dict[str, object]] = []
    multipliers = trade_policy.get("calibrationLowerMultipliers", {})
    if not isinstance(multipliers, dict):
        multipliers = {}
    model_weight = float(trade_policy.get("modelWeight", 0))
    temperature = float(trade_policy.get("temperature", 1))
    required_margin = 0.05
    for _, snapshot in snapshots.iterrows():
        line = float(snapshot["line"])
        over_odds = float(snapshot["over_odds"])
        under_odds = float(snapshot["under_odds"])
        if not 1 < over_odds <= 1000 or not 1 < under_odds <= 1000:
            continue
        raw_over = 1 / over_odds
        raw_under = 1 / under_odds
        market_over = raw_over / (raw_over + raw_under)
        model_over = model.over_probability(
            float(record["expectedTotalCorners"]),
            line,
        )
        model_logit = np.log(model_over / (1 - model_over))
        market_logit = np.log(market_over / (1 - market_over))
        blended_over = 1 / (
            1
            + np.exp(
                -(
                    model_weight * model_logit
                    + (1 - model_weight) * market_logit
                )
                / temperature
            )
        )
        directions = []
        for direction, calibrated, odds in (
            ("over", blended_over, over_odds),
            ("under", 1 - blended_over, under_odds),
        ):
            key = f"{direction}:{line:g}:{odds_bucket(odds)}"
            conservative = calibrated * float(multipliers.get(key, 0))
            directions.append(
                {
                    "direction": direction,
                    "conservative_probability": conservative,
                    "odds": odds,
                    "ev": conservative * odds - 1,
                    "minimum_odds": (
                        required_margin + 1
                    ) / conservative
                    if conservative > 0
                    else float("inf"),
                }
            )
        best = max(directions, key=lambda value: float(value["ev"]))
        candidates.append(
            {
                **best,
                "snapshot": snapshot,
                "line": line,
                "over_odds": over_odds,
                "under_odds": under_odds,
            }
        )
    if not candidates:
        return record
    best = max(candidates, key=lambda value: float(value["ev"]))
    snapshot = best["snapshot"]
    maximum_odds = float(trade_policy.get("maximumOdds", 0))
    minimum_ev = float(trade_policy.get("minimumConservativeEv", 0))
    price_eligible = float(best["odds"]) >= float(best["minimum_odds"])
    trade_eligible = (
        bool(trade_policy.get("tradeEnabled", False))
        and price_eligible
        and float(best["odds"]) <= maximum_odds
        and float(best["ev"]) >= minimum_ev
    )
    if not bool(trade_policy.get("tradeEnabled", False)):
        reason = (
            "No bet：市場 challenger 未通過 validation／locked holdout，"
            "只顯示研究限價。"
        )
    elif not price_eligible:
        reason = "No bet：實際賠率低於保守機率計算的研究限價。"
    elif float(best["odds"]) > maximum_odds:
        reason = "No bet：賠率高於已驗證政策上限。"
    elif float(best["ev"]) < minimum_ev:
        reason = "No bet：保守 EV 未達已驗證最低門檻。"
    else:
        reason = "只供虛擬模擬：實際價格達到已驗證研究限價。"
    record.update(
        {
            "marketAvailable": True,
            "marketSource": str(snapshot["source"]),
            "marketCapturedAt": pd.Timestamp(
                snapshot["captured_at"]
            ).isoformat(),
            "marketLine": best["line"],
            "marketOverOdds": best["over_odds"],
            "marketUnderOdds": best["under_odds"],
            "conservativeProbability": round(
                float(best["conservative_probability"]),
                6,
            ),
            "minimumAcceptableOdds": (
                round(float(best["minimum_odds"]), 4)
                if np.isfinite(float(best["minimum_odds"]))
                else None
            ),
            "researchDirection": best["direction"],
            "tradeEligible": trade_eligible,
            "tradeReason": reason,
        }
    )
    return record


def _recent_backtests(
    model: ForecastModel,
    league: LeagueConfig,
    count: int = 12,
) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    recent = model.out_of_fold.sort_values("Date").tail(count)
    for _, row in recent.iterrows():
        record = _base_record(
            row,
            float(row["PredictedHomeCorners"]),
            float(row["PredictedAwayCorners"]),
            model,
            league,
        )
        record.update(
            {
                "mode": "backtest",
                "actualTotalCorners": int(row["TotalCorners"]),
                "confidence": "backtest",
                "confidenceScore": 0.0,
                "recommendation": "history-only",
                "forecastStage": "候選外歷史評估",
                "dataQuality": 1.0,
                "modelStability": 0.0,
                "factors": [],
            }
        )
        records.append(record)
    return records


def _settlement_results(
    model: ForecastModel,
    league: LeagueConfig,
    count: int = 500,
) -> list[dict[str, object]]:
    recent = model.out_of_fold.sort_values("Date").tail(count)
    return [
        {
            "matchId": _match_id(league.code, row),
            "leagueCode": league.code,
            "date": pd.Timestamp(row["Date"]).date().isoformat(),
            "homeTeam": str(row["HomeTeam"]),
            "awayTeam": str(row["AwayTeam"]),
            "actualTotalCorners": int(row["TotalCorners"]),
        }
        for _, row in recent.iterrows()
    ]


def _model_summary(
    bundle: DataBundle,
    league: LeagueConfig,
    model: ForecastModel,
    trade_policy: dict[str, object],
) -> dict[str, object]:
    target = bundle.target_history[league.code]
    support_count = int(
        bundle.history["Division"].eq(league.support_code).sum()
    )
    labels = bundle.season_labels[league.code]
    return {
        "name": "EdgeWise league-specific model tournament",
        "version": MODEL_VERSION,
        "selectedCandidate": model.candidate,
        "selectedCandidateLabel": (
            "Recency-Weighted Count Model"
            if model.candidate == "poisson_recent"
            else model.candidate
        ),
        "trainedThrough": pd.Timestamp(target["Date"].max()).date().isoformat(),
        "firstSeason": labels[0],
        "lastSeason": labels[-1],
        "trainingMatches": int(len(target)),
        "supportMatches": support_count,
        "supportName": league.support_name,
        "dispersion": round(model.dispersion, 4),
        "tradePolicy": trade_policy,
        "drift": _historical_drift(model),
        "metrics": model.metrics,
    }


def _historical_drift(
    model: ForecastModel,
    window: int = 100,
) -> dict[str, object]:
    ordered = model.out_of_fold.sort_values("Date")
    recent = ordered.tail(window)
    reference = ordered.iloc[max(0, len(ordered) - window * 2) : -len(recent)]
    if len(recent) < 30 or len(reference) < 30:
        return {
            "status": "insufficient",
            "recentMatches": int(len(recent)),
            "referenceMatches": int(len(reference)),
            "recentMaeTotalCorners": 0.0,
            "referenceMaeTotalCorners": 0.0,
            "recentBrierOver9_5": 0.0,
            "referenceBrierOver9_5": 0.0,
        }

    def metrics(frame: pd.DataFrame) -> tuple[float, float]:
        mae = float(
            np.mean(
                np.abs(
                    frame["TotalCorners"].to_numpy(dtype=float)
                    - frame["PredictedTotalCorners"].to_numpy(dtype=float)
                )
            )
        )
        probabilities = np.array(
            [
                model.over_probability(float(mean), 9.5)
                for mean in frame["PredictedTotalCorners"]
            ],
            dtype=float,
        )
        actual = frame["TotalCorners"].gt(9.5).to_numpy(dtype=float)
        return mae, float(np.mean((probabilities - actual) ** 2))

    recent_mae, recent_brier = metrics(recent)
    reference_mae, reference_brier = metrics(reference)
    status = "stable"
    if (
        recent_mae > reference_mae * 1.35
        or recent_brier > reference_brier + 0.06
    ):
        status = "stop"
    elif (
        recent_mae > reference_mae * 1.15
        or recent_brier > reference_brier + 0.03
    ):
        status = "watch"
    return {
        "status": status,
        "recentMatches": int(len(recent)),
        "referenceMatches": int(len(reference)),
        "recentMaeTotalCorners": round(recent_mae, 4),
        "referenceMaeTotalCorners": round(reference_mae, 4),
        "recentBrierOver9_5": round(recent_brier, 6),
        "referenceBrierOver9_5": round(reference_brier, 6),
    }


def _disabled_trade_policy(reason: str) -> dict[str, object]:
    return {
        "status": "challenger-only",
        "tradeEnabled": False,
        "reason": reason,
        "marketDataRows": 0,
        "forecastStage": "T-10m",
    }


def _football_trade_policy(
    model: ForecastModel,
    league: LeagueConfig,
    market_frame: pd.DataFrame | None,
) -> dict[str, object]:
    if market_frame is None or market_frame.empty:
        return _disabled_trade_policy(
            "未提供帶時間戳的角球市場歷史檔；只顯示統計研究預測。"
        )
    snapshots = select_pre_match_snapshots(market_frame, lead_minutes=10)
    snapshots = snapshots.loc[
        snapshots["match_id"].astype(str).str.startswith(f"{league.code}:")
        & snapshots["line"].mod(1).eq(0.5)
    ]
    if snapshots.empty:
        return _disabled_trade_policy(
            "沒有可配對此聯賽的T-10m雙向角球市場快照。"
        )
    predictions = model.out_of_fold.copy()
    predictions["match_id"] = predictions.apply(
        lambda row: _match_id(league.code, row),
        axis=1,
    )
    joined = snapshots.merge(
        predictions[
            [
                "match_id",
                "Date",
                "PredictedTotalCorners",
                "TotalCorners",
            ]
        ],
        on="match_id",
        how="inner",
    )
    if joined.empty:
        return _disabled_trade_policy(
            "市場快照未能配對候選外評估賽事。"
        )
    joined["date"] = pd.to_datetime(joined["Date"]).dt.date.astype(str)
    joined["model_over_probability"] = [
        model.over_probability(float(mean), float(line))
        for mean, line in zip(
            joined["PredictedTotalCorners"],
            joined["line"],
            strict=True,
        )
    ]
    joined["over_won"] = joined["TotalCorners"].gt(joined["line"])
    joined = add_two_way_market_probabilities(joined).dropna(
        subset=["market_over_probability"]
    )
    dates = np.sort(joined["date"].unique())
    if len(dates) < 20:
        return _disabled_trade_policy(
            "完整市場快照少於20個比賽日。"
        )
    development_end = max(1, int(len(dates) * 0.7))
    validation_end = max(development_end + 1, int(len(dates) * 0.85))
    development = joined.loc[joined["date"].isin(dates[:development_end])]
    validation = joined.loc[
        joined["date"].isin(dates[development_end:validation_end])
    ]
    locked = joined.loc[joined["date"].isin(dates[validation_end:])]
    if development.empty or validation.empty or locked.empty:
        return _disabled_trade_policy(
            "Development、validation及locked市場切分不完整。"
        )
    blend = select_market_blend(development)
    development_probability = blend_over_probability(
        development,
        blend.model_weight,
        blend.temperature,
    )
    multipliers = calibration_lower_multipliers(
        development,
        development_probability,
    )
    validation = apply_conservative_probabilities(
        validation,
        blend,
        multipliers,
    )
    policy = select_trade_policy(validation, minimum_bets=30)
    locked = apply_conservative_probabilities(
        locked,
        blend,
        multipliers,
    )
    locked_selections = policy_selections(
        locked,
        maximum_odds=policy.maximum_odds,
        minimum_conservative_ev=policy.minimum_conservative_ev,
    )
    locked_lower_roi = bootstrap_roi_lower(
        locked_selections,
        seed=202608,
    )
    locked_passed = (
        len(locked_selections) >= 30 and locked_lower_roi > 0
    )
    trade_enabled = policy.trade_enabled and locked_passed
    if trade_enabled:
        reason = "Validation及locked holdout市場閘門均通過。"
    elif not policy.trade_enabled:
        reason = policy.reason
    elif len(locked_selections) < 30:
        reason = "Locked holdout合資格虛擬注項少於30。"
    else:
        reason = "Locked holdout bootstrap ROI下限不是正數。"
    return {
        "status": "validated" if trade_enabled else "challenger-only",
        "tradeEnabled": trade_enabled,
        "reason": reason,
        "marketDataRows": int(len(joined)),
        "forecastStage": "T-10m",
        "source": "Betfair Historical Data Basic",
        "lastCapturedAt": str(snapshots["captured_at"].max()),
        "modelWeight": round(blend.model_weight, 4),
        "temperature": round(blend.temperature, 4),
        "validationBets": policy.validation_bets,
        "validationRoi": round(policy.validation_roi, 6),
        "validationBootstrapLowerRoi": round(
            policy.bootstrap_lower_roi,
            6,
        ),
        "lockedBets": int(len(locked_selections)),
        "lockedRoi": round(unit_roi(locked_selections), 6),
        "lockedBootstrapLowerRoi": round(locked_lower_roi, 6),
        "minimumConservativeEv": policy.minimum_conservative_ev,
        "maximumOdds": policy.maximum_odds,
        "stakeFraction": 0.005,
        "fractionalKelly": 0.1,
        "maximumMatchExposure": 0.005,
        "maximumMatchDayExposure": 0.02,
        "drawdownStop": 0.15,
        "calibrationLowerMultipliers": multipliers,
    }


def _league_payload(
    bundle: DataBundle,
    league: LeagueConfig,
    market_frame: pd.DataFrame | None,
    *,
    understat_cache: Path | None = None,
    fbref_cache: Path | None = None,
    api_football_key: str = "",
    visual_crossing_key: str = "",
) -> tuple[dict[str, object], list[dict[str, object]]]:
    relevant = bundle.history.loc[
        bundle.history["Division"].isin((league.code, league.support_code))
    ]
    builder = FeatureBuilder(league.code, league.support_code)
    history_features = builder.fit_transform_history(relevant)

    # --- Enrich with new data sources ---
    season_labels = bundle.season_labels.get(league.code, ())
    season_strs = [f"{int(s.split('/')[0])}/{s.split('/')[1]}" for s in season_labels]

    # 1. Understat xG features (free, no key needed)
    if understat_cache:
        try:
            xg_frame = build_understat_frame(league.code, understat_cache, season_strs)
            history_features = add_xg_features(history_features, xg_frame, league.code)
        except Exception:
            pass

    # 2. FBref team style features (free, no key needed)
    if fbref_cache:
        try:
            fbref_frame = build_fbref_frame(league.code, fbref_cache, season_strs)
            history_features = add_fbref_features(history_features, fbref_frame, league.code)
        except Exception:
            pass

    # 3. API-Football injuries (needs RapidAPI key)
    if api_football_key:
        try:
            inj_cache = (fbref_cache or understat_cache or Path("data/raw")) / "injuries"
            history_features = build_injury_features(
                history_features, league.code, api_football_key, inj_cache
            )
        except Exception:
            pass

    # 4. Visual Crossing historical wind (needs API key)
    if visual_crossing_key:
        try:
            vc_cache = (fbref_cache or understat_cache or Path("data/raw")) / "weather"
            history_features = add_wind_features(
                history_features, league.code, visual_crossing_key, vc_cache
            )
        except Exception:
            pass
    # --- End enrichment ---

    model = train_walk_forward(history_features, feature_columns(history_features))
    trade_policy = _football_trade_policy(model, league, market_frame)
    fixtures = bundle.fixtures.loc[bundle.fixtures["Div"].eq(league.code)]
    fixture_features = builder.transform_fixtures(fixtures)
    forecasts: list[dict[str, object]] = []
    if not fixture_features.empty:
        home, away = model.predict(fixture_features)
        forecasts = [
            _attach_market_decision(
                _forecast_record(
                    row,
                    home[index],
                    away[index],
                    model,
                    league,
                ),
                model,
                market_frame,
                trade_policy,
            )
            for index, (_, row) in enumerate(fixture_features.iterrows())
        ]
    payload = {
        "code": league.code,
        "name": league.name,
        "supportCode": league.support_code,
        "supportName": league.support_name,
        "sourceUrl": league.country_url,
        "status": (
            f"已找到 {len(forecasts)} 場未來賽事"
            if forecasts
            else "目前來源尚未發布未來賽程，暫示最近候選外評估"
        ),
        "model": _model_summary(bundle, league, model, trade_policy),
        "forecasts": forecasts,
        "recentBacktests": _recent_backtests(model, league),
    }
    return payload, _settlement_results(model, league)


def _build_payload(
    bundle: DataBundle,
    racing_payload: dict[str, object],
    market_frame: pd.DataFrame | None = None,
    *,
    understat_cache: Path | None = None,
    fbref_cache: Path | None = None,
    api_football_key: str = "",
    visual_crossing_key: str = "",
) -> dict[str, object]:
    generated_at = datetime.now(timezone.utc)
    league_payloads: list[dict[str, object]] = []
    settlement_results: list[dict[str, object]] = []
    for league in LEAGUES:
        league_payload, results = _league_payload(
            bundle,
            league,
            market_frame,
            understat_cache=understat_cache,
            fbref_cache=fbref_cache,
            api_football_key=api_football_key,
            visual_crossing_key=visual_crossing_key,
        )
        league_payloads.append(league_payload)
        settlement_results.extend(results)

    version_input = (
        f"{MODEL_VERSION}:{bundle.fingerprint}:"
        + ":".join(
            f"{league['code']}:{league['model']['selectedCandidate']}"
            for league in league_payloads
        )
        + f":racing:{racing_payload.get('model', {}).get('trainedThrough', '')}:"
        + ":".join(
            str(race.get("raceId", "")) for race in racing_payload.get("races", [])
        )
    )
    return {
        "schemaVersion": 2,
        "dataVersion": hashlib.sha256(version_input.encode()).hexdigest()[:16],
        "generatedAt": generated_at.isoformat(),
        "source": {
            "name": "Football-Data.co.uk CSV and personal-research HKJC pages",
            "url": "https://www.football-data.co.uk/data.php",
            "lastModified": bundle.source_last_modified,
            "licenseNotice": (
                "HKJC access is low-frequency, cached and personal/non-commercial; "
                "confirm every source term before any publication or redistribution."
            ),
        },
        "leagues": league_payloads,
        "settlementResults": settlement_results,
        "racing": racing_payload,
        "disclaimer": (
            "Statistical analysis and virtual simulation only. "
            "Predictions are uncertain and are not financial advice."
        ),
    }


def run_pipeline(
    output_path: Path,
    cache_dir: Path,
    first_start_year: int = 2000,
    market_data_path: Path | None = None,
    *,
    understat_cache: Path | None = None,
    fbref_cache: Path | None = None,
    api_football_key: str = "",
    visual_crossing_key: str = "",
) -> dict[str, object]:
    bundle = load_data(cache_dir=cache_dir, first_start_year=first_start_year)
    market_frame = None
    if market_data_path is not None and market_data_path.exists():
        market_frame = pd.read_csv(market_data_path)
    payload = _build_payload(
        bundle,
        build_racing_payload(cache_dir.parent / "racing" / "latest.json"),
        market_frame,
        understat_cache=understat_cache,
        fbref_cache=fbref_cache,
        api_football_key=api_football_key,
        visual_crossing_key=visual_crossing_key,
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(".tmp")
    temporary_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    temporary_path.replace(output_path)
    return payload
