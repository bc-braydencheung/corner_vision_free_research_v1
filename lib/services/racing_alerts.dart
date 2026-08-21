import '../models/forecast_data.dart';
import '../models/racing_mobile.dart';
import 'market_timeline.dart';
import 'research_alerts.dart';

/// Edge a runner must carry before the summary card mentions it.
///
/// Higher than the corner threshold on purpose: the win pool charges far more
/// takeout than the corner pool, and a field of a dozen runners leaves much
/// more room for probability error than a two-sided line.
const racingMinimumEdge = 0.05;

/// One runner the model prices above the HKJC win pool.
///
/// The runner tile shows no expected value at all, so the value is computed
/// here from the same published win pool the app already stores: the vig-free
/// pool probability against the model probability the tile displays.
class RacingAlert implements ResearchAlert {
  const RacingAlert({
    required this.race,
    required this.runner,
    required this.marketOdds,
    required this.marketProbability,
    required this.capturedAt,
  });

  final RacingRace race;
  final RacingRunner runner;

  /// Win odds quoted by HKJC when the snapshot was captured.
  final double marketOdds;

  /// Pool probability with the takeout removed.
  final double marketProbability;
  final DateTime capturedAt;

  String get horseName => runner.horseNameChinese.isNotEmpty
      ? runner.horseNameChinese
      : runner.horseName;

  @override
  double get odds => marketOdds;

  @override
  double get edge => runner.winProbability * marketOdds - 1;

  @override
  double get confidence => runner.confidenceScore;

  @override
  String get confidenceLabel => switch (runner.confidence) {
    'high' => '高',
    'medium' => '中',
    _ => '低',
  };

  @override
  String get context => '${race.venue} 第${race.raceNumber}場';

  @override
  String get subject => '${runner.number} $horseName';

  @override
  String get market => '獨贏';

  @override
  DateTime get startTime => race.startTime;
}

/// Every runner priced above the win pool, best edge first.
///
/// Nothing is surfaced unless the racing model itself is cleared to speak: a
/// closed trade gate, an unavailable summary, a runner the model declines, a
/// race already off, or a race without a stored pool all yield no alert. The
/// quote used is the newest snapshot captured before the race, so no final
/// (post-race) price ever becomes a pre-race signal.
List<RacingAlert> buildRacingAlerts({
  required RacingSummary racing,
  required List<RacingOddsSnapshot> snapshots,
  required DateTime asOf,
  double minimumEdge = racingMinimumEdge,
}) {
  if (!racing.available || !racing.model.tradeEnabled) {
    return const [];
  }
  final latest = <String, RacingOddsSnapshot>{};
  for (final snapshot in snapshots) {
    if (snapshot.isFinal || snapshot.oddsByHorse.length < 2) {
      continue;
    }
    final current = latest[snapshot.raceId];
    if (current == null || snapshot.capturedAt.isAfter(current.capturedAt)) {
      latest[snapshot.raceId] = snapshot;
    }
  }
  final alerts = <RacingAlert>[];
  for (final race in racing.races) {
    if (!race.startTime.isAfter(asOf)) {
      continue;
    }
    final snapshot = latest[race.raceId];
    if (snapshot == null) {
      continue;
    }
    final fair = poolProbabilities(snapshot.oddsByHorse);
    for (final runner in race.runners) {
      if (runner.recommendation == 'no-prediction') {
        continue;
      }
      final key = _quoteKey(snapshot.oddsByHorse, runner);
      final quoted = key == null ? null : snapshot.oddsByHorse[key];
      final marketProbability = key == null ? null : fair[key];
      if (quoted == null || marketProbability == null || quoted <= 1) {
        continue;
      }
      final alert = RacingAlert(
        race: race,
        runner: runner,
        marketOdds: quoted,
        marketProbability: marketProbability,
        capturedAt: snapshot.capturedAt,
      );
      if (runner.winProbability <= marketProbability ||
          alert.edge < minimumEdge) {
        continue;
      }
      alerts.add(alert);
    }
  }
  alerts.sort((a, b) => b.edge.compareTo(a.edge));
  return alerts;
}

/// Snapshot key holding [runner]'s quote, mirroring the engine's own lookup:
/// the stable horse code when HKJC published one, otherwise the saddle number.
String? _quoteKey(Map<String, double> quotes, RacingRunner runner) {
  for (final candidate in [
    runner.horseId,
    runner.number.toString().padLeft(2, '0'),
    runner.number.toString(),
  ]) {
    if (quotes.containsKey(candidate)) {
      return candidate;
    }
  }
  return null;
}
