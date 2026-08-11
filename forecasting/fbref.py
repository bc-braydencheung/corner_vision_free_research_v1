from __future__ import annotations

import time
import urllib.request
from io import StringIO
from pathlib import Path

import pandas as pd

USER_AGENT = "EdgeWise/1.0 personal statistical research"

FBREF_LEAGUES = {
    "E0": ("Premier-League", "https://fbref.com/en/comps/9/"),
    "SP1": ("La-Liga", "https://fbref.com/en/comps/12/"),
    "D1": ("Bundesliga", "https://fbref.com/en/comps/20/"),
    "I1": ("Serie-A", "https://fbref.com/en/comps/11/"),
    "F1": ("Ligue-1", "https://fbref.com/en/comps/13/"),
}

SQUAD_STATS_COLS = [
    "crosses_per90", "touches_att_pen_area_per90",
    "possession_pct", "pass_completion_pct",
    "fouls_drawn_per90", "corners_per90_fbref",
]

COLUMN_MAP = {
    "Crosses": "crosses_per90",
    "Touches": None,
    "Att Pen": "touches_att_pen_area_per90",
    "Poss": "possession_pct",
    "Cmp%": "pass_completion_pct",
    "Fld": "fouls_drawn_per90",
    "CK": "corners_per90_fbref",
}


def _scrape_table(url: str, table_id: str, cache_path: Path) -> pd.DataFrame:
    if cache_path.exists():
        return pd.read_csv(cache_path)

    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        html = response.read().decode("utf-8", errors="replace")

    tables = pd.read_html(StringIO(html), attrs={"id": table_id})
    if not tables:
        raise ValueError(f"Table {table_id} not found at {url}")
    frame = tables[0]
    if isinstance(frame.columns, pd.MultiIndex):
        frame.columns = ["_".join(str(l) for l in col if "Unnamed" not in str(l)).strip("_")
                         for col in frame.columns]
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(cache_path, index=False)
    time.sleep(0.5)
    return frame


def fetch_team_stats(league_code: str, season: str, cache_dir: Path) -> pd.DataFrame:
    if league_code not in FBREF_LEAGUES:
        return pd.DataFrame()
    league_name, base_url = FBREF_LEAGUES[league_code]
    season_slug = f"{season.split('/')[0]}-{season.split('/')[1]}"
    url = f"{base_url}{season_slug}/{season_slug}-{league_name}-Stats"
    cache_path = cache_dir / "fbref" / f"{league_code}_{season}_squad.csv"

    try:
        frame = _scrape_table(url, "stats_squads_standard_for", cache_path)
    except Exception:
        return pd.DataFrame()

    if frame.empty:
        return pd.DataFrame()

    # Extract team name from first column
    first_col = frame.columns[0]
    frame["team"] = frame[first_col].astype(str).str.strip()

    # Rename relevant columns
    rename_map = {}
    for col in frame.columns:
        for key, new_name in COLUMN_MAP.items():
            if key.lower() in col.lower() and new_name:
                rename_map[col] = new_name
                break

    frame = frame.rename(columns=rename_map)
    existing = [c for c in SQUAD_STATS_COLS if c in frame.columns]
    if not existing:
        return pd.DataFrame()

    result = frame[["team"] + existing].copy()
    result["league_code"] = league_code
    result["season"] = season
    # Convert to numeric
    for col in existing:
        result[col] = pd.to_numeric(result[col], errors="coerce")
    return result


def build_fbref_frame(
    league_code: str, cache_dir: Path, seasons: list[str]
) -> pd.DataFrame:
    frames = []
    for season in seasons:
        try:
            f = fetch_team_stats(league_code, season, cache_dir)
            if not f.empty:
                frames.append(f)
        except Exception:
            continue
    if not frames:
        return pd.DataFrame()
    return pd.concat(frames, ignore_index=True)


def add_fbref_features(
    matches: pd.DataFrame, fbref_frame: pd.DataFrame, league_code: str
) -> pd.DataFrame:
    """Add season-level team style features without leakage (use prior season)."""
    if fbref_frame.empty:
        return matches

    league_data = fbref_frame[fbref_frame["league_code"] == league_code].copy()
    if league_data.empty:
        return matches

    # For each match, find the prior season's team stats
    season_years = league_data["season"].unique()
    season_map = {}
    for sy in sorted(season_years):
        parts = sy.split("/")
        if len(parts) == 2:
            season_map[int(parts[0])] = sy

    stat_cols = [c for c in SQUAD_STATS_COLS if c in league_data.columns]
    if not stat_cols:
        return matches

    for side in ("home", "away"):
        for stat in stat_cols:
            dest = f"{side}_{stat}_prior"
            team_col = f"{side.capitalize()}Team"

            # Build team→season→stat lookup
            team_season_stat: dict[tuple[str, str], float] = {}
            for _, row in league_data.iterrows():
                key = (str(row["team"]).strip(), str(row["season"]))
                team_season_stat[key] = float(row[stat]) if pd.notna(row[stat]) else float("nan")

            def _map(row: pd.Series, _lookup=team_season_stat,
                     _season_map=season_map, _tc=team_col) -> float:
                match_year = pd.Timestamp(row["Date"]).year
                season_key = _season_map.get(match_year - 1, "")
                if not season_key:
                    season_key = _season_map.get(match_year, "")
                team = str(row[_tc]).strip()
                return float(_lookup.get((team, season_key), float("nan")))

            matches[dest] = matches.apply(_map, axis=1)

    for col in list(matches.columns):
        if col.endswith("_prior"):
            matches[col] = matches[col].fillna(
                matches[col].median() if not matches[col].isna().all() else 0
            )
    return matches
