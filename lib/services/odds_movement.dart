/// Reads the stored corner quotes as a multi-timepoint movement series.
///
/// The odds history is append-only, so the quote that stood 24, 6 and 1 hour
/// before kick-off can be recovered exactly instead of being approximated by
/// the latest price. Where the market moved between those points it moved on
/// information nobody publishes for free, which is why the movement itself is
/// worth recording separately from the price level.
///
/// Nothing here feeds the released model: the free settled history carries only
/// one closing price per match, so a movement column cannot be trained yet. The
/// series is measured, shown and stored so the evidence exists before any claim
/// is made about it.
library;

import 'dart:math';

import '../models/football_mobile.dart';
import 'market_timeline.dart';

/// Horizons before kick-off the market is read at, far to near.
const cornerMovementHorizons = <Duration>[
  Duration(hours: 24),
  Duration(hours: 6),
  Duration(hours: 1),
  Duration.zero,
];

/// Movement below this is noise from rounded decimal odds, not information.
const cornerMovementNoise = 0.005;

/// The quote that stood at one horizon before kick-off.
class CornerMovementPoint {
  const CornerMovementPoint({
    required this.horizon,
    required this.capturedAt,
    required this.fairOverProbability,
    required this.overOdds,
    required this.underOdds,
  });

  /// Time before kick-off this reading is anchored to; zero is the last
  /// pre-match quote.
  final Duration horizon;

  /// When the quote itself was captured; always at or before the horizon.
  final DateTime capturedAt;

  /// Margin-free probability of the over side at that moment.
  final double fairOverProbability;

  final double overOdds;
  final double underOdds;

  String get label => horizon == Duration.zero ? '開賽前' : '${horizon.inHours}h';
}

/// One corner line of one fixture, read at each horizon.
class CornerLineMovement {
  const CornerLineMovement({
    required this.matchId,
    required this.line,
    required this.points,
    required this.depth,
  });

  final String matchId;
  final double line;

  /// Readings that exist, ordered far to near. A horizon with no quote before
  /// it is left out rather than filled in from a later price.
  final List<CornerMovementPoint> points;

  /// Number of stored quotes of this line, including in-play ones.
  final int depth;

  bool get hasMovement => points.length >= 2;

  /// Change in the margin-free over probability across the whole series.
  double? get total => hasMovement
      ? points.last.fairOverProbability - points.first.fairOverProbability
      : null;

  /// Change between two consecutive readings, `null` when either is missing.
  double? segment(Duration from, Duration to) {
    final before = at(from);
    final after = at(to);
    if (before == null || after == null) {
      return null;
    }
    return after.fairOverProbability - before.fairOverProbability;
  }

  CornerMovementPoint? at(Duration horizon) {
    for (final point in points) {
      if (point.horizon == horizon) {
        return point;
      }
    }
    return null;
  }

  /// Consecutive changes between the readings that exist, far to near.
  List<double> get segments => [
    for (var index = 1; index < points.length; index++)
      points[index].fairOverProbability - points[index - 1].fairOverProbability,
  ];

  /// Whether every non-trivial change went the same way: steam, not chop.
  ///
  /// A single reading pair cannot show persistence, so at least two changes are
  /// required before the series is called consistent.
  bool get steaming {
    final moves = segments
        .where((move) => move.abs() >= cornerMovementNoise)
        .toList();
    if (moves.length < 2 || (total ?? 0).abs() < cornerMovementNoise) {
      return false;
    }
    return moves.every((move) => move > 0) || moves.every((move) => move < 0);
  }

  /// Side the market drifted towards, `null` when it barely moved.
  String? get direction {
    final move = total;
    if (move == null || move.abs() < cornerMovementNoise) {
      return null;
    }
    return move > 0 ? 'over' : 'under';
  }
}

/// Movement of every stored line of one fixture.
class FixtureOddsMovement {
  const FixtureOddsMovement({required this.matchId, required this.lines});

  final String matchId;

  /// Ascending by line.
  final List<CornerLineMovement> lines;

  /// Line the movement is reported from: the deepest series, and among equally
  /// deep ones the line closest to the 9.5 main market.
  CornerLineMovement? get primary {
    if (lines.isEmpty) {
      return null;
    }
    final ordered = [...lines]
      ..sort((left, right) {
        final depth = right.points.length.compareTo(left.points.length);
        if (depth != 0) {
          return depth;
        }
        final stored = right.depth.compareTo(left.depth);
        if (stored != 0) {
          return stored;
        }
        return (left.line - 9.5).abs().compareTo((right.line - 9.5).abs());
      });
    return ordered.first;
  }

  bool get hasMovement => primary?.hasMovement ?? false;
}

/// Builds the movement series of each fixture from the stored quote history.
///
/// [kickOffs] maps a HKJC match id to its kick-off time; a fixture without one
/// is skipped, because a horizon cannot be measured without the event time.
/// Matching is by match id only — never by team name.
Map<String, FixtureOddsMovement> cornerMovements({
  required List<FootballOddsSnapshot> snapshots,
  required Map<String, DateTime> kickOffs,
}) {
  final timelines = cornerTimelines(snapshots);
  final result = <String, FixtureOddsMovement>{};
  for (final entry in timelines.entries) {
    final kickOff = kickOffs[entry.key];
    if (kickOff == null) {
      continue;
    }
    final lines = <CornerLineMovement>[];
    for (final timeline in entry.value) {
      lines.add(_lineMovement(timeline, kickOff));
    }
    lines.sort((left, right) => left.line.compareTo(right.line));
    result[entry.key] = FixtureOddsMovement(matchId: entry.key, lines: lines);
  }
  return result;
}

CornerLineMovement _lineMovement(
  CornerLineTimeline timeline,
  DateTime kickOff,
) {
  final usable =
      timeline.observations
          .where(
            (snapshot) =>
                !snapshot.inPlay &&
                snapshot.capturedAt.toUtc().isBefore(kickOff.toUtc()) &&
                twoWayFairProbabilities(
                      snapshot.overOdds,
                      snapshot.underOdds,
                    ) !=
                    null,
          )
          .toList()
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  final points = <CornerMovementPoint>[];
  for (final horizon in cornerMovementHorizons) {
    final cutOff = kickOff.toUtc().subtract(horizon);
    FootballOddsSnapshot? candidate;
    for (final snapshot in usable) {
      if (!snapshot.capturedAt.toUtc().isAfter(cutOff)) {
        candidate = snapshot;
      }
    }
    if (candidate == null) {
      continue;
    }
    // The same quote can be the newest one at several horizons; recording it
    // twice would invent a zero move where the market simply did not requote.
    if (points.isNotEmpty &&
        points.last.capturedAt.isAtSameMomentAs(candidate.capturedAt)) {
      continue;
    }
    final fair = twoWayFairProbabilities(
      candidate.overOdds,
      candidate.underOdds,
    )!;
    points.add(
      CornerMovementPoint(
        horizon: horizon,
        capturedAt: candidate.capturedAt,
        fairOverProbability: fair.over,
        overOdds: candidate.overOdds,
        underOdds: candidate.underOdds,
      ),
    );
  }
  return CornerLineMovement(
    matchId: timeline.matchId,
    line: timeline.line,
    points: points,
    depth: timeline.depth,
  );
}

/// How much of the movement series the stored history actually covers.
class OddsMovementCoverage {
  const OddsMovementCoverage({
    required this.fixtures,
    required this.withMovement,
    required this.steaming,
    required this.meanAbsoluteMove,
  });

  static const empty = OddsMovementCoverage(
    fixtures: 0,
    withMovement: 0,
    steaming: 0,
    meanAbsoluteMove: 0,
  );

  /// Fixtures with at least one stored quote and a known kick-off.
  final int fixtures;

  /// Fixtures with at least two distinct readings, i.e. a measurable move.
  final int withMovement;

  /// Fixtures whose readings all moved the same way.
  final int steaming;

  /// Mean absolute total move, in probability, over [withMovement] fixtures.
  final double meanAbsoluteMove;

  String get summary {
    if (fixtures == 0) {
      return '尚未儲存任何盤口快照';
    }
    if (withMovement == 0) {
      return '$fixtures 場有快照，但每場只有單一時點，未能量度移動';
    }
    return '$withMovement／$fixtures 場可量度移動 · 平均 '
        '${(meanAbsoluteMove * 100).toStringAsFixed(1)} 個百分點 · '
        '單向 $steaming 場';
  }
}

OddsMovementCoverage summariseMovementCoverage(
  Map<String, FixtureOddsMovement> movements,
) {
  if (movements.isEmpty) {
    return OddsMovementCoverage.empty;
  }
  var withMovement = 0;
  var steaming = 0;
  var move = 0.0;
  for (final fixture in movements.values) {
    final primary = fixture.primary;
    if (primary == null || !primary.hasMovement) {
      continue;
    }
    withMovement++;
    move += (primary.total ?? 0).abs();
    if (primary.steaming) {
      steaming++;
    }
  }
  return OddsMovementCoverage(
    fixtures: movements.length,
    withMovement: withMovement,
    steaming: steaming,
    meanAbsoluteMove: withMovement == 0 ? 0 : move / max(withMovement, 1),
  );
}
