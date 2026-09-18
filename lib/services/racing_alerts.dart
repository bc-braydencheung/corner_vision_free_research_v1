import '../models/forecast_data.dart';
import '../models/pick_status.dart';
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
    required this.status,
  });

  final RacingRace race;
  final RacingRunner runner;

  /// Win odds quoted by HKJC when the snapshot was captured.
  final double marketOdds;

  /// Pool probability with the takeout removed.
  final double marketProbability;
  final DateTime capturedAt;

  @override
  final PickStatus status;

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

/// Proof standing behind one runner's pick.
///
/// Shared by the banner and the runner row so a closed gate reads the same in
/// both places: it downgrades the pick to [PickStatus.unverified] instead of
/// removing it, and only a runner the model prices above the pool by
/// [minimumEdge] while the gate is open is green.
PickStatus racingPickStatus({
  required bool declined,
  required bool gateOpen,
  required double modelProbability,
  required double marketProbability,
  required double edge,
  double minimumEdge = racingMinimumEdge,
}) {
  if (declined) {
    return PickStatus.insufficient;
  }
  return gateOpen && modelProbability > marketProbability && edge >= minimumEdge
      ? PickStatus.verified
      : PickStatus.unverified;
}

/// Each upcoming race's first choice, verified picks first.
///
/// A closed trade gate no longer silences the model: it downgrades the pick.
/// A race yields [PickStatus.verified] only while the gate is open and the
/// model prices its runner above the pool by [minimumEdge]; otherwise the
/// race's best runner is still named as [PickStatus.unverified], and a race
/// whose runners the model declines outright is [PickStatus.insufficient].
/// Races with no stored pool are skipped, since there is no price to quote.
/// The quote used is the newest snapshot captured before the race, so no
/// final (post-race) price ever becomes a pre-race signal.
List<RacingAlert> buildRacingAlerts({
  required RacingSummary racing,
  required List<RacingOddsSnapshot> snapshots,
  required DateTime asOf,
  double minimumEdge = racingMinimumEdge,
}) {
  if (!racing.available) {
    return const [];
  }
  final gateOpen = racing.model.tradeEnabled;
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
    RacingAlert? best;
    for (final runner in race.runners) {
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
        status: racingPickStatus(
          declined: runner.recommendation == 'no-prediction',
          gateOpen: gateOpen,
          modelProbability: runner.winProbability,
          marketProbability: marketProbability,
          edge: runner.winProbability * quoted - 1,
          minimumEdge: minimumEdge,
        ),
      );
      if (best == null ||
          alert.status.index < best.status.index ||
          (alert.status == best.status && alert.edge > best.edge)) {
        best = alert;
      }
    }
    if (best != null) {
      alerts.add(best);
    }
  }
  alerts.sort((a, b) {
    final byStatus = a.status.index.compareTo(b.status.index);
    return byStatus != 0 ? byStatus : b.edge.compareTo(a.edge);
  });
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
