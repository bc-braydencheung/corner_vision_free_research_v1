from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path

import pandas as pd

from forecasting.racing_model import FEATURE_COLUMNS, EntityState, RacingFeatureBuilder


def _state(value: EntityState) -> list[object]:
    return [
        value.starts,
        value.wins,
        value.places,
        round(value.finish_total, 6),
        value.last_date.isoformat() if value.last_date else "",
        [round(item, 6) for item in value.recent],
        {str(key): count for key, count in value.distance_starts.items()},
        {str(key): count for key, count in value.distance_wins.items()},
    ]


def build_mobile_seed(history_path: Path) -> dict[str, object]:
    history = pd.read_csv(history_path)
    builder = RacingFeatureBuilder()
    frame = builder.fit_transform(history)
    frame = frame.sort_values(["date", "race_id", "horse_id"])
    rows = [
        [
            str(row.race_id),
            str(row.date),
            int(row.field_size),
            int(row.won),
            int(row.placed),
            *[
                round(float(getattr(row, feature) or 0.0), 6)
                for feature in FEATURE_COLUMNS
            ],
        ]
        for row in frame.itertuples()
    ]
    encoded_rows = json.dumps(rows, separators=(",", ":")).encode()
    return {
        "schemaVersion": 1,
        "datasetVersion": hashlib.sha256(encoded_rows).hexdigest()[:20],
        "trainedThrough": str(pd.to_datetime(history["date"]).max().date()),
        "featureNames": list(FEATURE_COLUMNS),
        "rows": rows,
        "horses": {
            key: _state(value)
            for key, value in sorted(builder.horses.items())
        },
        "jockeys": {
            key: _state(value)
            for key, value in sorted(builder.jockeys.items())
        },
        "trainers": {
            key: _state(value)
            for key, value in sorted(builder.trainers.items())
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build the private mobile racing training seed."
    )
    parser.add_argument("--history", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    payload = build_mobile_seed(args.history)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(args.output, "wt", encoding="utf-8", compresslevel=9) as output:
        json.dump(payload, output, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
