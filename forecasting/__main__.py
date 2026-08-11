from __future__ import annotations

import argparse
import os
from pathlib import Path

from forecasting.pipeline import run_pipeline


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train and publish European league corner forecasts."
    )
    parser.add_argument("--output", type=Path,
                        default=Path("assets/data/latest.json"))
    parser.add_argument("--cache-dir", type=Path,
                        default=Path("data/raw"))
    parser.add_argument("--first-season", type=int, default=2000)
    parser.add_argument("--market-data", type=Path,
                        help="Optional immutable Betfair corner-market snapshot CSV.")

    # New enriched data sources
    parser.add_argument("--understat-cache", type=Path,
                        default=Path("data/understat"),
                        help="Cache dir for Understat xG data (free, no key needed).")
    parser.add_argument("--fbref-cache", type=Path,
                        default=Path("data/fbref"),
                        help="Cache dir for FBref team stats (free, no key needed).")
    parser.add_argument("--api-football-key", type=str, default="",
                        help="RapidAPI key for API-Football (injuries).")
    parser.add_argument("--visual-crossing-key", type=str, default="",
                        help="Visual Crossing API key for historical weather.")

    args = parser.parse_args()

    # Also check environment variables for API keys
    api_key = args.api_football_key or os.environ.get("API_FOOTBALL_KEY", "")
    vc_key = args.visual_crossing_key or os.environ.get("VISUAL_CROSSING_KEY", "")

    payload = run_pipeline(
        args.output,
        args.cache_dir,
        args.first_season,
        args.market_data,
        understat_cache=args.understat_cache,
        fbref_cache=args.fbref_cache,
        api_football_key=api_key,
        visual_crossing_key=vc_key,
    )
    summaries = ", ".join(
        f"{league['name']}={league['model']['selectedCandidate']}"
        for league in payload["leagues"]
    )
    sources = ["Football-Data"]
    if args.understat_cache:
        sources.append("Understat xG+shots")
    if args.fbref_cache:
        sources.append("FBref")
    if api_key:
        sources.append("API-Football")
    if vc_key:
        sources.append("VisualCrossing")
    print(
        f"Generated {args.output} for {len(payload['leagues'])} leagues "
        f"[sources: {', '.join(sources)}]; {summaries}."
    )


if __name__ == "__main__":
    main()
