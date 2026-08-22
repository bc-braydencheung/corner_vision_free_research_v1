/// Analytics over stored odds time series.
///
/// The app records every HKJC quote it displays with its capture time and never
/// overwrites an earlier quote, so the stored history can be replayed to obtain
/// the opening quote, the closing quote (the last quote before the event
/// starts) and the drift between them. The closing quote is the reference the
/// research pages grade model probabilities against, because it arrives before
/// the result and carries far more information per event than the result does.
library;

import 'dart:math';

import '../models/football_mobile.dart';
import '../models/racing_mobile.dart';

/// Removes the bookmaker margin from a two-way market.
///
/// Returns null for a pair of prices no two-way market can carry: decimal odds
/// at or below evens on both sides, a non-finite value or a missing quote. A
/// price like that is a broken payload, and silently clamping it into range
/// would hand a fabricated probability to every grader downstream.
({double over, double under})? twoWayFairProbabilities(
  double overOdds,
  double underOdds,
) {
  if (!_pricesUsable(overOdds, underOdds)) {
    return null;
  }
  final rawOver = 1 / overOdds;
  final rawUnder = 1 / underOdds;
  final total = rawOver + rawUnder;
  return (over: rawOver / total, under: rawUnder / total);
}

/// Bookmaker margin of a two-way market, e.g. `0.08` for an 8% take.
///
/// Null for prices a two-way market cannot carry, as [twoWayFairProbabilities].
double? twoWayOverround(double overOdds, double underOdds) =>
    _pricesUsable(overOdds, underOdds)
    ? 1 / overOdds + 1 / underOdds - 1
    : null;

/// Whether a two-way pair of decimal odds can be read as a market at all.
bool _pricesUsable(double overOdds, double underOdds) =>
    overOdds.isFinite &&
    underOdds.isFinite &&
    overOdds > 1 &&
    underOdds > 1 &&
    // A book summing below one prices an arbitrage, which HKJC never offers:
    // such a pair is a corrupt payload rather than a gift.
    1 / overOdds + 1 / underOdds >= 1 - 1e-9;

/// One corner (`CHL`) line of one fixture, ordered by capture time.
class CornerLineTimeline {
  CornerLineTimeline({
    required this.matchId,
    required this.line,
    required this.observations,
  });

  final String matchId;
  final double line;

  /// Ascending by [FootballOddsSnapshot.capturedAt]; never mutated in place.
  final List<FootballOddsSnapshot> observations;

  FootballOddsSnapshot? get opening =>
      observations.isEmpty ? null : observations.first;

  FootballOddsSnapshot? get latest =>
      observations.isEmpty ? null : observations.last;

  /// Last quote captured before [kickOff], i.e. the closing line.
  FootballOddsSnapshot? closing(DateTime kickOff) {
    final before = observations
        .where(
          (snapshot) =>
              !snapshot.inPlay &&
              snapshot.capturedAt.toUtc().isBefore(kickOff.toUtc()),
        )
        .toList();
    return before.isEmpty ? null : before.last;
  }

  /// Change in the margin-free over probability from opening to closing.
  double? drift(DateTime kickOff) {
    final first = opening;
    final last = closing(kickOff);
    if (first == null || last == null || first.capturedAt == last.capturedAt) {
      return null;
    }
    final before = _fairOver(first);
    final after = _fairOver(last);
    if (before == null || after == null) {
      return null;
    }
    return after - before;
  }

  /// Number of distinct quotes recorded for this line.
  int get depth => observations.length;

  static double? _fairOver(FootballOddsSnapshot snapshot) =>
      twoWayFairProbabilities(snapshot.overOdds, snapshot.underOdds)?.over;
}

/// Groups stored corner snapshots into per-fixture, per-line timelines.
Map<String, List<CornerLineTimeline>> cornerTimelines(
  List<FootballOddsSnapshot> snapshots,
) {
  final grouped = <String, Map<double, List<FootballOddsSnapshot>>>{};
  for (final snapshot in snapshots) {
    grouped
        .putIfAbsent(
          snapshot.matchId,
          () => <double, List<FootballOddsSnapshot>>{},
        )
        .putIfAbsent(snapshot.line, () => <FootballOddsSnapshot>[])
        .add(snapshot);
  }
  final result = <String, List<CornerLineTimeline>>{};
  for (final match in grouped.entries) {
    final lines = <CornerLineTimeline>[];
    for (final line in match.value.entries) {
      final ordered = [...line.value]
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
      lines.add(
        CornerLineTimeline(
          matchId: match.key,
          line: line.key,
          observations: ordered,
        ),
      );
    }
    lines.sort((left, right) => left.line.compareTo(right.line));
    result[match.key] = lines;
  }
  return result;
}

/// Closing-line value of one graded selection.
///
/// [modelProbability] is the probability the model held when the selection was
/// made, [takenOdds] the quote available at that moment and [closingOdds] the
/// last quote before the event. Positive [oddsValue] means the quote taken was
/// better than the closing quote, which is the fastest available evidence that
/// the model found real value.
class ClosingLineValue {
  const ClosingLineValue({
    required this.modelProbability,
    required this.takenOdds,
    required this.closingOdds,
    required this.closingFairProbability,
  });

  final double modelProbability;
  final double takenOdds;
  final double closingOdds;
  final double closingFairProbability;

  /// Relative price advantage against the closing quote.
  double get oddsValue => takenOdds / closingOdds - 1;

  /// Expected value of the taken quote under the closing market probability.
  double get closingExpectedValue => closingFairProbability * takenOdds - 1;

  /// How far the model disagreed with the closing market, in probability.
  double get disagreement => modelProbability - closingFairProbability;

  bool get beatClosing => oddsValue > 0;
}

/// Aggregate closing-line report used by the research health page.
class ClosingLineReport {
  const ClosingLineReport({
    required this.graded,
    required this.beatClosingRate,
    required this.meanOddsValue,
    required this.meanClosingExpectedValue,
    required this.meanAbsoluteDisagreement,
  });

  static const empty = ClosingLineReport(
    graded: 0,
    beatClosingRate: 0,
    meanOddsValue: 0,
    meanClosingExpectedValue: 0,
    meanAbsoluteDisagreement: 0,
  );

  final int graded;
  final double beatClosingRate;
  final double meanOddsValue;
  final double meanClosingExpectedValue;
  final double meanAbsoluteDisagreement;

  bool get hasSignal => graded >= 20;

  String get verdict {
    if (!hasSignal) {
      return '收盤價樣本不足（$graded 筆），未足以評估';
    }
    if (meanOddsValue > 0.01) {
      return '平均打敗收盤價 ${(meanOddsValue * 100).toStringAsFixed(1)}%';
    }
    if (meanOddsValue > -0.01) {
      return '與收盤價持平';
    }
    return '落後收盤價 ${(-meanOddsValue * 100).toStringAsFixed(1)}%';
  }
}

ClosingLineReport summariseClosingLineValue(List<ClosingLineValue> values) {
  if (values.isEmpty) {
    return ClosingLineReport.empty;
  }
  var beat = 0;
  var oddsValue = 0.0;
  var expectedValue = 0.0;
  var disagreement = 0.0;
  for (final value in values) {
    if (value.beatClosing) {
      beat++;
    }
    oddsValue += value.oddsValue;
    expectedValue += value.closingExpectedValue;
    disagreement += value.disagreement.abs();
  }
  final count = values.length;
  return ClosingLineReport(
    graded: count,
    beatClosingRate: beat / count,
    meanOddsValue: oddsValue / count,
    meanClosingExpectedValue: expectedValue / count,
    meanAbsoluteDisagreement: disagreement / count,
  );
}

/// Win-odds timeline of one race, ordered by capture time.
class RaceOddsTimeline {
  RaceOddsTimeline({required this.raceId, required this.snapshots});

  final String raceId;

  /// Ascending by [RacingOddsSnapshot.capturedAt].
  final List<RacingOddsSnapshot> snapshots;

  RacingOddsSnapshot? get opening => snapshots.isEmpty ? null : snapshots.first;

  RacingOddsSnapshot? get closing {
    final finals = snapshots.where((snapshot) => snapshot.isFinal).toList();
    return finals.isNotEmpty
        ? finals.last
        : snapshots.isEmpty
        ? null
        : snapshots.last;
  }

  /// Margin-free win probabilities of the closing pool.
  Map<String, double> closingProbabilities() {
    final close = closing;
    if (close == null) {
      return const {};
    }
    return poolProbabilities(close.oddsByHorse);
  }

  /// Horses whose margin-free probability moved by at least [threshold]
  /// between the opening and the closing pool: late money.
  Map<String, double> lateMoney({double threshold = 0.02}) {
    final first = opening;
    final last = closing;
    if (first == null || last == null || first.capturedAt == last.capturedAt) {
      return const {};
    }
    final before = poolProbabilities(first.oddsByHorse);
    final after = poolProbabilities(last.oddsByHorse);
    final moves = <String, double>{};
    for (final entry in after.entries) {
      final previous = before[entry.key];
      if (previous == null) {
        continue;
      }
      final move = entry.value - previous;
      if (move.abs() >= threshold) {
        moves[entry.key] = move;
      }
    }
    return moves;
  }
}

/// Converts a HKJC win pool into probabilities that sum to one.
///
/// The quoted odds already include the pool takeout, so the raw reciprocals sum
/// to roughly `1 / (1 - takeout)`; normalising them removes the take.
Map<String, double> poolProbabilities(Map<String, double> oddsByHorse) {
  final raw = <String, double>{};
  var total = 0.0;
  for (final entry in oddsByHorse.entries) {
    if (!entry.value.isFinite || entry.value <= 1) {
      continue;
    }
    final probability = 1 / entry.value;
    raw[entry.key] = probability;
    total += probability;
  }
  if (total <= 0) {
    return const {};
  }
  return {for (final entry in raw.entries) entry.key: entry.value / total};
}

/// Corrects the favourite–longshot bias of pool probabilities.
///
/// Public pools systematically overbet longshots, so raising every probability
/// to a power above one and renormalising shifts weight back to the favourites.
/// [exponent] of `1.0` leaves the pool untouched.
Map<String, double> favouriteLongshotAdjusted(
  Map<String, double> probabilities, {
  double exponent = 1.18,
}) {
  if (probabilities.isEmpty) {
    return const {};
  }
  final powered = <String, double>{};
  var total = 0.0;
  for (final entry in probabilities.entries) {
    final value = pow(max(entry.value, 1e-9), exponent).toDouble();
    powered[entry.key] = value;
    total += value;
  }
  return {for (final entry in powered.entries) entry.key: entry.value / total};
}

RaceOddsTimeline raceTimeline(
  String raceId,
  List<RacingOddsSnapshot> snapshots,
) {
  final ordered =
      snapshots.where((snapshot) => snapshot.raceId == raceId).toList()
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  return RaceOddsTimeline(raceId: raceId, snapshots: ordered);
}
