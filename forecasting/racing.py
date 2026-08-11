from __future__ import annotations

import argparse
import json
from datetime import date, datetime, timezone
from pathlib import Path

from forecasting.hkjc import HKJCScraper, result_records
from forecasting.hkjc_trials import build_trial_features
from forecasting.racing_model import build_predictions, train_racing_model

RACE_FIELDS = {
    "raceId",
    "date",
    "startTime",
    "venue",
    "raceNumber",
    "raceName",
    "distanceMetres",
    "surface",
    "runners",
}
RUNNER_FIELDS = {
    "horseId",
    "horseName",
    "number",
    "draw",
    "jockey",
    "trainer",
    "winProbability",
    "placeProbability",
    "fairWinOdds",
    "fairPlaceOdds",
    "confidence",
    "confidenceScore",
}


def build_racing_payload(path: Path | None = None) -> dict[str, object]:
    unavailable = {
        "sport": "香港賽馬",
        "modelVersion": "racing-1.0.0",
        "generatedAt": None,
        "sourceUrl": "https://racing.hkjc.com/en-us/local/information",
        "available": False,
        "status": "個人研究爬蟲尚未產生足夠歷史資料及預測。",
        "races": [],
        "results": [],
        "model": {},
        "sourceNotice": (
            "只供個人非商業研究；採低頻率及本機快取，不公開或再發布"
            "香港賽馬會原始頁面、賠率或資料庫。"
        ),
    }
    if path is None or not path.exists():
        return unavailable

    payload = json.loads(path.read_text(encoding="utf-8"))
    races = payload.get("races")
    if not isinstance(races, list):
        raise ValueError("Racing payload must contain a races list.")
    for race in races:
        if not isinstance(race, dict) or not RACE_FIELDS.issubset(race):
            raise ValueError("Racing payload contains an invalid race.")
        runners = race["runners"]
        if not isinstance(runners, list) or not runners:
            raise ValueError("Every racing payload race must contain runners.")
        for runner in runners:
            if not isinstance(runner, dict) or not RUNNER_FIELDS.issubset(runner):
                raise ValueError("Racing payload contains an invalid runner.")
        probability_sum = sum(float(runner["winProbability"]) for runner in runners)
        if not 0.98 <= probability_sum <= 1.02:
            raise ValueError("Runner win probabilities must sum to one per race.")
        expected_places = 3 if len(runners) >= 7 else 2 if len(runners) >= 4 else 0
        place_sum = sum(float(runner["placeProbability"]) for runner in runners)
        if abs(place_sum - expected_places) > 0.03:
            raise ValueError(
                "Runner place probabilities must match the race place slots."
            )

    return {
        "sport": "香港賽馬",
        "modelVersion": payload.get("modelVersion", "racing-1.0.0"),
        "generatedAt": payload.get("generatedAt"),
        "sourceUrl": payload.get(
            "sourceUrl",
            "https://racing.hkjc.com/en-us/local/information",
        ),
        "available": bool(payload.get("available", races)),
        "status": payload.get("status", "已載入個人研究版香港賽馬預測。"),
        "races": races,
        "results": payload.get("results", []),
        "model": payload.get("model", {}),
        "sourceNotice": payload.get(
            "sourceNotice",
            "只供個人非商業研究，不公開或再發布原始資料。",
        ),
    }


def refresh_racing_payload(
    output: Path,
    cache_dir: Path,
    start: date,
    end: date,
    max_requests: int | None = None,
    min_interval_seconds: float = 0.75,
) -> dict[str, object]:
    scraper = HKJCScraper(
        cache_dir / "html",
        min_interval_seconds=min_interval_seconds,
    )
    history = scraper.sync_history(
        cache_dir / "history.csv",
        start=start,
        end=end,
        max_requests=max_requests,
    )
    # Enrich with barrier trial features (free, no key needed)
    try:
        history = build_trial_features(history, cache_dir / "trials")
    except Exception:
        pass
    model, builder, _ = train_racing_model(history)
    races = scraper.upcoming_races()
    predictions = build_predictions(model, builder, races)
    model_metrics = {
        **model.metrics,
        "firstSeason": _season_label(str(history["date"].min())),
        "lastSeason": _season_label(str(history["date"].max())),
        "trainingSeasons": len(
            {
                _season_label(str(value))
                for value in history["date"].dropna()
            }
        ),
        "tradePolicy": {
            "status": "challenger-only",
            "tradeEnabled": False,
            "reason": (
                "固定時間全場賠率快照及市場基準驗證尚未通過；"
                "只顯示統計研究預測。"
            ),
        },
    }
    payload = {
        "sport": "香港賽馬",
        "modelVersion": "racing-1.0.0",
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "sourceUrl": "https://racing.hkjc.com/en-us/local/information",
        "available": True,
        "status": (
            f"個人研究模型已用 {model.metrics['trainingRaces']} 場訓練賽事及 "
            f"{model.metrics['holdoutRaces']} 場日期留出賽事評估。"
        ),
        "races": predictions,
        "results": result_records(history),
        "model": model_metrics,
        "sourceNotice": (
            "資料源為香港賽馬會公開賽果及排位頁；只供個人非商業研究。"
            "爬蟲設低頻率及本機快取，payload 不包含原始網頁或完整資料庫；"
            "網站條款或頁面結構改變時應立即停用及重新核對。"
        ),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return payload


def _season_label(value: str) -> str:
    parsed = date.fromisoformat(value[:10])
    start = parsed.year if parsed.month >= 8 else parsed.year - 1
    return f"{start}/{str(start + 1)[-2:]}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Refresh the personal-research HKJC racing model."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/racing/latest.json"),
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("data/racing"),
    )
    parser.add_argument("--start-date", type=date.fromisoformat, required=True)
    parser.add_argument("--end-date", type=date.fromisoformat, default=date.today())
    parser.add_argument("--max-requests", type=int)
    parser.add_argument("--interval", type=float, default=0.75)
    args = parser.parse_args()
    payload = refresh_racing_payload(
        output=args.output,
        cache_dir=args.cache_dir,
        start=args.start_date,
        end=args.end_date,
        max_requests=args.max_requests,
        min_interval_seconds=args.interval,
    )
    print(
        f"Generated {args.output}: {len(payload['races'])} upcoming races; "
        f"{payload['model']['trainingRaces']} training races."
    )


if __name__ == "__main__":
    main()
