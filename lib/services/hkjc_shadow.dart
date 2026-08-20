import '../models/football_mobile.dart';
import '../models/forecast_data.dart';
import '../models/hkjc_football.dart';
import '../models/shadow_forecast.dart';
import '../models/team_news.dart';
import 'calibration_service.dart';
import 'corner_strength_service.dart';
import 'hkjc_corner_model.dart';
import 'hkjc_football_service.dart';
import 'market_anchor.dart';
import 'market_residual.dart';
import 'online_learning.dart';
import 'two_stage_corner_model.dart';

/// Line every stored forecast is scored on, matching `over9_5Probability`.
const shadowCornerLine = 9.5;

/// A finished HKJC match is only settled once its corner count can no longer
/// change, which the free feed does not flag: the running result of a live
/// match carries partial corners under the same field.
const shadowSettlementDelay = Duration(hours: 3);

/// Metrics of the dataset model the stored forecast is judged against.
class ShadowModelReference {
  const ShadowModelReference({
    required this.version,
    required this.mae,
    required this.brier,
  });

  final String version;
  final double mae;
  final double brier;
}

/// Adds the HKJC fixtures the corner model can price to the shadow ledger and
/// settles the ones whose corner count is known.
///
/// The ledger used to be filled from the free football-data fixture list only,
/// which keys a match as `E0:date:home:away` while every stored HKJC quote is
/// keyed by the HKJC match id. Those two keys never met, so a stored forecast
/// could not be paired with the price it was made at. Recording the HKJC
/// fixture under the HKJC key makes the forecast, the quote series and the
/// settled corner count share one identifier.
List<ShadowForecast> updateHkjcShadow({
  required List<ShadowForecast> existing,
  required HkjcFootballSnapshot? snapshot,
  required Map<String, String> leagueNames,
  required Map<String, ShadowModelReference> references,
  required DateTime asOf,
  List<MatchResult> settlementResults = const [],
  MarketCalibration? calibration,
  CornerPriorTables priors = CornerPriorTables.empty,
  Map<String, FootballWeatherSnapshot> weather = const {},
  Map<String, TeamNewsSnapshot> teamNews = const {},
  OnlineLearningState? online,
  MarketAnchorState? anchor,
  MarketResidualState? residual,
}) {
  final byId = {for (final record in existing) record.id: record};
  final datasetKeyed = <String, String>{
    for (final record in existing)
      if (record.actualTotalCorners == null)
        shadowBridgeKey(
          leagueCode: record.leagueCode,
          date: record.matchDate,
          homeTeam: record.homeTeam,
          awayTeam: record.awayTeam,
        ): record.id,
  };
  final now = asOf.toUtc();
  final current = snapshot;
  if (current != null) {
    for (final code in hkjcFootballProfiles.keys) {
      final reference = references[code];
      final strengths = priors.strengths[code];
      final shots = priors.shots[code];
      final joint = priors.joint[code];
      for (final fixture in current.forLeague(code)) {
        final home = fixture.homeTeamEnglish.isEmpty
            ? fixture.homeTeam
            : fixture.homeTeamEnglish;
        final away = fixture.awayTeamEnglish.isEmpty
            ? fixture.awayTeam
            : fixture.awayTeamEnglish;
        final kickOff = fixture.kickOffTime.toUtc();
        final version = reference?.version ?? 'hkjc-corner';
        final id = '${fixture.matchId}:$version';
        if (byId.containsKey(id) || !kickOff.isAfter(now)) {
          continue;
        }
        if (!fixture.cornerLines.any(
          (line) => line.line == shadowCornerLine && line.hasOdds,
        )) {
          continue;
        }
        final assessment = HkjcCornerModel(
          calibration: calibration,
          prior: combineCornerPriors(
            strengths?.priorFor(
              homeTeam: home,
              awayTeam: away,
              kickOff: fixture.kickOffTime,
            ),
            shots?.priorFor(
              homeTeam: home,
              awayTeam: away,
              kickOff: fixture.kickOffTime,
            ),
          ),
          weather: weather[fixture.matchId],
          online: online,
          anchor: anchor,
          residual: residual,
          joint: joint,
          homeNews: teamNews[fixture.homeTeam],
          awayNews: teamNews[fixture.awayTeam],
        ).assess(fixture);
        if (assessment == null) {
          continue;
        }
        final scored = assessment.lines
            .where((line) => line.line.line == shadowCornerLine)
            .firstOrNull;
        if (scored == null || !scored.modelHighProbability.isFinite) {
          continue;
        }
        byId[id] = ShadowForecast(
          id: id,
          matchId: fixture.matchId,
          leagueCode: code,
          leagueName: leagueNames[code] ?? code,
          homeTeam: home,
          awayTeam: away,
          matchDate: fixture.kickOffTime,
          capturedAt: now,
          modelVersion: version,
          expectedTotalCorners: assessment.expectedCorners,
          over9_5Probability: scored.modelHighProbability.clamp(1e-4, 1 - 1e-4),
          referenceMae: reference?.mae ?? 0,
          referenceBrier: reference?.brier ?? 0,
          marketOverProbability:
              scored.marketHighProbability > 0 &&
                  scored.marketHighProbability < 1
              ? scored.marketHighProbability
              : null,
        );
        final duplicate =
            datasetKeyed[shadowBridgeKey(
              leagueCode: code,
              date: fixture.kickOffTime,
              homeTeam: home,
              awayTeam: away,
            )];
        if (duplicate != null && duplicate != id) {
          byId.remove(duplicate);
        }
      }
    }
  }
  final hkjcResults = <String, int>{};
  for (final fixture in current?.fixtures ?? const <HkjcFootballFixture>[]) {
    final home = fixture.homeCorner;
    final away = fixture.awayCorner;
    if (home == null ||
        away == null ||
        home < 0 ||
        away < 0 ||
        now.isBefore(fixture.kickOffTime.toUtc().add(shadowSettlementDelay))) {
      continue;
    }
    hkjcResults[fixture.matchId] = home + away;
  }
  final datasetResults = _datasetResults(settlementResults);
  for (final entry in byId.entries.toList()) {
    final record = entry.value;
    if (record.actualTotalCorners != null) {
      continue;
    }
    final actual =
        hkjcResults[record.matchId] ??
        datasetResults[shadowBridgeKey(
          leagueCode: record.leagueCode,
          date: record.matchDate,
          homeTeam: record.homeTeam,
          awayTeam: record.awayTeam,
        )];
    if (actual == null) {
      continue;
    }
    byId[entry.key] = record.settle(
      actual,
      now.isAfter(record.matchDate.toUtc()) ? now : record.matchDate.toUtc(),
    );
  }
  return byId.values.toList()
    ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
}

/// Free-feed results indexed by league, kick-off day and normalised team names.
///
/// The HKJC key cannot appear in the free dataset, so a match that left the
/// HKJC feed before its corners were read is settled through the only other
/// free result source available.
Map<String, int> _datasetResults(List<MatchResult> results) {
  final indexed = <String, int>{};
  for (final result in results) {
    final parts = result.matchId.split(':');
    if (parts.length != 4) {
      continue;
    }
    final date = DateTime.tryParse(parts[1]);
    if (date == null) {
      continue;
    }
    indexed[shadowBridgeKey(
          leagueCode: parts[0],
          date: date,
          homeTeam: parts[2],
          awayTeam: parts[3],
        )] =
        result.actualTotalCorners;
  }
  return indexed;
}

/// Key that pairs the same fixture across the HKJC feed and the free dataset.
String shadowBridgeKey({
  required String leagueCode,
  required DateTime date,
  required String homeTeam,
  required String awayTeam,
}) {
  final day = DateTime.utc(
    date.toUtc().year,
    date.toUtc().month,
    date.toUtc().day,
  );
  return '$leagueCode:${day.toIso8601String().substring(0, 10)}'
      ':${normaliseTeamKey(homeTeam)}:${normaliseTeamKey(awayTeam)}';
}

/// Reduces a team name to the letters both feeds agree on.
///
/// The two free feeds punctuate and abbreviate differently, so punctuation,
/// spacing and the common club suffixes are removed before comparing. Names
/// that disagree on letters (`Atl. Madrid` against `Ath Madrid`) still do not
/// meet, and such a fixture is simply left unsettled rather than paired with a
/// guess.
String normaliseTeamKey(String name) {
  var value = name.toLowerCase();
  for (final token in const [' fc', 'fc ', ' cf', 'cf ', ' afc', ' ac ']) {
    value = value.replaceAll(token, ' ');
  }
  return value.replaceAll(RegExp(r'[^a-z0-9]'), '');
}
