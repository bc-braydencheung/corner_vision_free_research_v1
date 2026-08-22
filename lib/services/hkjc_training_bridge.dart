import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../models/shadow_forecast.dart';
import 'hkjc_shadow.dart';

/// Clubs the two feeds abbreviate so differently that dropping punctuation is
/// not enough, keyed by the normalised HKJC name.
///
/// Each value is still looked up in the division's own history before it is
/// used, so an entry naming a club that division does not carry is skipped like
/// any other unresolved name. A name two tracked clubs could both answer to is
/// deliberately absent rather than guessed.
const _aliases = <String, String>{
  'manchestercity': 'Man City',
  'manchesterutd': 'Man United',
  'manchesterunited': 'Man United',
  'nottinghamforest': "Nott'm Forest",
  'parissaintgermain': 'Paris SG',
  'atleticomadrid': 'Ath Madrid',
  'athleticbilbao': 'Ath Bilbao',
  'athleticclub': 'Ath Bilbao',
  'realsociedad': 'Sociedad',
  'realbetis': 'Betis',
  'celtavigo': 'Celta',
  'rayovallecano': 'Vallecano',
  'espanyol': 'Espanol',
  'realvalladolid': 'Valladolid',
  'realoviedo': 'Oviedo',
  'deportivoalaves': 'Alaves',
  'intermilan': 'Inter',
  'acmilan': 'Milan',
  'actorino': 'Torino',
  'torinofc': 'Torino',
  'hellasverona': 'Verona',
  'angerssco': 'Angers',
  'saintetienne': 'St Etienne',
  'olympiquelyonnais': 'Lyon',
  'olympiquemarseille': 'Marseille',
  'stadereims': 'Reims',
  'staderennais': 'Rennes',
};

/// History rows the settled HKJC corner results add to the free football
/// history.
///
/// The free CSV history publishes a finished match days later, while the HKJC
/// corner count of the same match is stored the moment the match is over.
/// Feeding those counts into the history lets the model learn from the most
/// recent rounds instead of waiting for the free feed.
///
/// A result is only admitted when both club names resolve to clubs the free
/// history already carries in that division: an unresolved name is skipped
/// rather than added under a name of its own, which would split one club's form
/// across two identities. A match the free history already carries is skipped
/// as well, so the published row always wins over the reading — that row also
/// carries the goals and shots the reading does not have.
///
/// Only the corner counts are filled in. Every other column stays null, which
/// the feature builder reads as absent rather than as a zero.
List<FootballMatchRecord> hkjcTrainingRows({
  required MobileFootballDataset dataset,
  required List<ShadowForecast> forecasts,
  required List<HkjcCornerResult> results,
  required DateTime asOf,
}) {
  final totals = observedCornerTotals(results, asOf: asOf);
  final splits = {
    for (final result in results)
      if (totals[result.matchId] == result.totalCorners) result.matchId: result,
  };
  if (splits.isEmpty) {
    return const [];
  }
  final canonical = <String, String>{};
  final published = <String>{};
  for (final row in dataset.rows) {
    canonical['${row.division}:${normaliseTeamKey(row.homeTeam)}'] =
        row.homeTeam;
    canonical['${row.division}:${normaliseTeamKey(row.awayTeam)}'] =
        row.awayTeam;
    final date = DateTime.tryParse(row.date);
    if (date == null) {
      continue;
    }
    published.add(
      shadowBridgeKey(
        leagueCode: row.division,
        date: date,
        homeTeam: row.homeTeam,
        awayTeam: row.awayTeam,
      ),
    );
  }
  final rows = <FootballMatchRecord>[];
  final added = <String>{};
  for (final forecast in forecasts) {
    final result = splits[forecast.matchId];
    if (result == null) {
      continue;
    }
    final home = _resolve(canonical, forecast.leagueCode, forecast.homeTeam);
    final away = _resolve(canonical, forecast.leagueCode, forecast.awayTeam);
    if (home == null || away == null || home == away) {
      continue;
    }
    // The free feed files a late kick-off on the neighbouring calendar day, so
    // the day either side counts as published too.
    final keys = [
      for (final shift in const [0, -1, 1])
        shadowBridgeKey(
          leagueCode: forecast.leagueCode,
          date: forecast.matchDate.toUtc().add(Duration(days: shift)),
          homeTeam: home,
          awayTeam: away,
        ),
    ];
    if (keys.any(published.contains) || keys.any(added.contains)) {
      continue;
    }
    added.add(keys.first);
    rows.add(
      FootballMatchRecord(
        division: forecast.leagueCode,
        date: result.kickOffTime.toUtc().toIso8601String().substring(0, 10),
        homeTeam: home,
        awayTeam: away,
        homeCorners: result.homeCorner,
        awayCorners: result.awayCorner,
      ),
    );
  }
  return rows;
}

/// The free history's own spelling of [name], or null when the two feeds cannot
/// be shown to mean the same club.
String? _resolve(
  Map<String, String> canonical,
  String leagueCode,
  String name,
) {
  final key = normaliseTeamKey(name);
  final alias = _aliases[key];
  return canonical['$leagueCode:$key'] ??
      (alias == null
          ? null
          : canonical['$leagueCode:${normaliseTeamKey(alias)}']);
}

/// [dataset] with the HKJC corner results appended, in match order.
MobileFootballDataset withHkjcTrainingRows({
  required MobileFootballDataset dataset,
  required List<ShadowForecast> forecasts,
  required List<HkjcCornerResult> results,
  required DateTime asOf,
}) {
  final extra = hkjcTrainingRows(
    dataset: dataset,
    forecasts: forecasts,
    results: results,
    asOf: asOf,
  );
  if (extra.isEmpty) {
    return dataset;
  }
  final rows = [...dataset.rows, ...extra]
    ..sort((left, right) => left.date.compareTo(right.date));
  return MobileFootballDataset(
    schemaVersion: dataset.schemaVersion,
    // The version has to move with the rows, or a training job resumed from a
    // checkpoint would keep training on the history without them.
    datasetVersion: '${dataset.datasetVersion}+hkjc${extra.length}',
    generatedAt: dataset.generatedAt,
    leagues: dataset.leagues,
    rows: rows,
    fixtures: dataset.fixtures,
  );
}
