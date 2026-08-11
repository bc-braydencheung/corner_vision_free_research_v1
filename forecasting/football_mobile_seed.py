from __future__ import annotations

import gzip
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from forecasting.data import LEAGUES, DataBundle, load_data


NUMERIC_COLUMNS = (
    "HC",
    "AC",
    "FTHG",
    "FTAG",
    "HS",
    "AS",
    "HST",
    "AST",
    "AvgH",
    "AvgD",
    "AvgA",
    "Avg>2.5",
    "Avg<2.5",
)


def _number(row: pd.Series, column: str) -> int | float | None:
    value = row.get(column)
    if pd.isna(value):
        return None
    number = float(value)
    return int(number) if number.is_integer() else round(number, 5)


def build_football_mobile_seed(bundle: DataBundle) -> dict[str, object]:
    rows: list[list[object]] = []
    for _, row in bundle.history.sort_values(
        ["Date", "Division", "HomeTeam", "AwayTeam"]
    ).iterrows():
        rows.append(
            [
                str(row["Division"]),
                pd.Timestamp(row["Date"]).date().isoformat(),
                str(row["HomeTeam"]),
                str(row["AwayTeam"]),
                *[_number(row, column) for column in NUMERIC_COLUMNS],
            ]
        )
    version_source = json.dumps(rows, ensure_ascii=False, separators=(",", ":"))
    return {
        "schemaVersion": 1,
        "datasetVersion": hashlib.sha256(version_source.encode()).hexdigest()[:16],
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "leagues": [
            {
                "code": league.code,
                "name": league.name,
                "supportCode": league.support_code,
                "supportName": league.support_name,
            }
            for league in LEAGUES
        ],
        "rows": rows,
    }


def write_football_mobile_seed(
    output_path: Path,
    cache_dir: Path,
    first_start_year: int = 2000,
) -> dict[str, object]:
    payload = build_football_mobile_seed(
        load_data(cache_dir=cache_dir, first_start_year=first_start_year)
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(
        payload,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode()
    temporary = output_path.with_suffix(output_path.suffix + ".tmp")
    temporary.write_bytes(gzip.compress(encoded, compresslevel=9))
    temporary.replace(output_path)
    return payload


if __name__ == "__main__":
    write_football_mobile_seed(
        Path("assets/data/football_mobile_seed.json.gz"),
        Path("data/raw"),
    )
