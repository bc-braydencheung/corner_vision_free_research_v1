/// Purged walk-forward validation with a temporal embargo.
///
/// A single hold-out at the end of the history flatters any model whose
/// features are rolling averages: the last training match and the first test
/// match share the same window, so information leaks across the boundary. This
/// splits the history into consecutive folds and, around every boundary, drops
/// (purges) the training matches whose feature window reaches into the test
/// fold and then waits out an embargo before scoring, which is the lottery-free
/// version of the purged K-fold idea from financial machine learning.
library;

import 'dart:math';

/// One train/test split with its purged and embargoed boundary.
class WalkForwardFold {
  const WalkForwardFold({
    required this.index,
    required this.trainIndices,
    required this.testIndices,
    required this.trainEnd,
    required this.testStart,
    required this.testEnd,
    required this.purged,
    required this.embargoed,
  });

  final int index;

  /// Indices into the caller's date-ordered row list.
  final List<int> trainIndices;
  final List<int> testIndices;
  final DateTime trainEnd;
  final DateTime testStart;
  final DateTime testEnd;

  /// Training rows dropped because their feature window overlapped the test
  /// fold.
  final int purged;

  /// Test rows dropped because they fell inside the embargo after the boundary.
  final int embargoed;
}

/// Score of one fold against the free baseline on the same rows.
class WalkForwardFoldMetrics {
  const WalkForwardFoldMetrics({
    required this.mae,
    required this.baselineMae,
    required this.brier,
    required this.baselineBrier,
    required this.samples,
  });

  final double mae;
  final double baselineMae;
  final double brier;
  final double baselineBrier;
  final int samples;

  /// Whether the model beat the baseline on both metrics in this fold.
  bool get beatsBaseline => mae < baselineMae && brier <= baselineBrier;

  Map<String, Object?> toJson() => {
    'mae': mae,
    'baselineMae': baselineMae,
    'brier': brier,
    'baselineBrier': baselineBrier,
    'samples': samples,
  };

  static WalkForwardFoldMetrics fromJson(Map<String, Object?> json) =>
      WalkForwardFoldMetrics(
        mae: (json['mae'] as num).toDouble(),
        baselineMae: (json['baselineMae'] as num).toDouble(),
        brier: (json['brier'] as num).toDouble(),
        baselineBrier: (json['baselineBrier'] as num).toDouble(),
        samples: (json['samples'] as num).toInt(),
      );
}

/// Aggregate of every fold, and the gate the model has to pass.
class WalkForwardReport {
  const WalkForwardReport({
    required this.folds,
    required this.purgeDays,
    required this.embargoDays,
    required this.purgedRows,
    required this.embargoedRows,
  });

  static const empty = WalkForwardReport(
    folds: [],
    purgeDays: 0,
    embargoDays: 0,
    purgedRows: 0,
    embargoedRows: 0,
  );

  factory WalkForwardReport.fromJson(Map<String, Object?> json) =>
      WalkForwardReport(
        folds: (json['folds'] as List<Object?>? ?? const [])
            .map(
              (value) => WalkForwardFoldMetrics.fromJson(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList(),
        purgeDays: (json['purgeDays'] as num?)?.toInt() ?? 0,
        embargoDays: (json['embargoDays'] as num?)?.toInt() ?? 0,
        purgedRows: (json['purgedRows'] as num?)?.toInt() ?? 0,
        embargoedRows: (json['embargoedRows'] as num?)?.toInt() ?? 0,
      );

  final List<WalkForwardFoldMetrics> folds;
  final int purgeDays;
  final int embargoDays;
  final int purgedRows;
  final int embargoedRows;

  int get foldCount => folds.length;
  int get passedFolds => folds.where((fold) => fold.beatsBaseline).length;
  int get samples => folds.fold<int>(0, (sum, fold) => sum + fold.samples);

  double get mae => _weighted((fold) => fold.mae);
  double get baselineMae => _weighted((fold) => fold.baselineMae);
  double get brier => _weighted((fold) => fold.brier);
  double get baselineBrier => _weighted((fold) => fold.baselineBrier);

  /// Brier skill against the baseline; positive means the model added value.
  double get skill =>
      baselineBrier <= 0 ? 0 : 1 - brier / max(baselineBrier, 1e-9);

  /// A model is only released when it wins most folds, not just on average:
  /// one lucky window is exactly what a single hold-out cannot tell apart from
  /// a real edge.
  bool get gatePassed =>
      foldCount >= 3 &&
      passedFolds * 2 > foldCount &&
      mae < baselineMae &&
      brier <= baselineBrier;

  String get verdict {
    if (foldCount < 3) {
      return '樣本不足，未做 purged walk-forward，維持基準';
    }
    return gatePassed
        ? '通過 $passedFolds/$foldCount 折 · Brier 技巧 '
              '${(skill * 100).toStringAsFixed(1)}%'
        : '只通過 $passedFolds/$foldCount 折，未達放行門檻';
  }

  Map<String, Object?> toJson() => {
    'folds': folds.map((fold) => fold.toJson()).toList(),
    'purgeDays': purgeDays,
    'embargoDays': embargoDays,
    'purgedRows': purgedRows,
    'embargoedRows': embargoedRows,
  };
}

/// Builds purged, embargoed, expanding-window folds over date-ordered [dates].
///
/// [dates] must be sorted ascending; the caller owns the row order so the
/// returned indices can be applied to any parallel list.
List<WalkForwardFold> purgedWalkForwardFolds({
  required List<DateTime> dates,
  int folds = 4,
  Duration purge = const Duration(days: 10),
  Duration embargo = const Duration(days: 3),
  int minimumTrain = 150,
  int minimumTest = 30,
}) {
  if (folds < 1 || dates.length < minimumTrain + minimumTest) {
    return const [];
  }
  final built = <WalkForwardFold>[];
  final span = dates.length - minimumTrain;
  final step = span ~/ folds;
  if (step < minimumTest) {
    return const [];
  }
  for (var fold = 0; fold < folds; fold++) {
    final testStartIndex = minimumTrain + fold * step;
    final testEndIndex = fold == folds - 1
        ? dates.length
        : min(testStartIndex + step, dates.length);
    if (testEndIndex - testStartIndex < minimumTest) {
      break;
    }
    final boundary = dates[testStartIndex];
    final embargoUntil = boundary.add(embargo);
    final purgeFrom = boundary.subtract(purge);
    final trainIndices = <int>[];
    var purged = 0;
    for (var index = 0; index < testStartIndex; index++) {
      if (dates[index].isBefore(purgeFrom)) {
        trainIndices.add(index);
      } else {
        purged += 1;
      }
    }
    final testIndices = <int>[];
    var embargoed = 0;
    for (var index = testStartIndex; index < testEndIndex; index++) {
      if (dates[index].isBefore(embargoUntil)) {
        embargoed += 1;
      } else {
        testIndices.add(index);
      }
    }
    if (trainIndices.length < minimumTrain ~/ 2 || testIndices.isEmpty) {
      continue;
    }
    built.add(
      WalkForwardFold(
        index: fold,
        trainIndices: trainIndices,
        testIndices: testIndices,
        trainEnd: dates[trainIndices.last],
        testStart: dates[testIndices.first],
        testEnd: dates[testIndices.last],
        purged: purged,
        embargoed: embargoed,
      ),
    );
  }
  return built;
}

/// Runs [evaluate] on every purged fold of [rows] and aggregates the scores.
WalkForwardReport runPurgedWalkForward<R>({
  required List<R> rows,
  required DateTime Function(R row) dateOf,
  required WalkForwardFoldMetrics? Function(List<R> train, List<R> test)
  evaluate,
  int folds = 4,
  Duration purge = const Duration(days: 10),
  Duration embargo = const Duration(days: 3),
  int minimumTrain = 150,
  int minimumTest = 30,
}) {
  final ordered = [...rows]
    ..sort((left, right) => dateOf(left).compareTo(dateOf(right)));
  final dates = ordered.map(dateOf).toList(growable: false);
  final splits = purgedWalkForwardFolds(
    dates: dates,
    folds: folds,
    purge: purge,
    embargo: embargo,
    minimumTrain: minimumTrain,
    minimumTest: minimumTest,
  );
  final metrics = <WalkForwardFoldMetrics>[];
  var purgedRows = 0;
  var embargoedRows = 0;
  for (final split in splits) {
    final scored = evaluate(
      [for (final index in split.trainIndices) ordered[index]],
      [for (final index in split.testIndices) ordered[index]],
    );
    purgedRows += split.purged;
    embargoedRows += split.embargoed;
    if (scored != null) {
      metrics.add(scored);
    }
  }
  return WalkForwardReport(
    folds: metrics,
    purgeDays: purge.inDays,
    embargoDays: embargo.inDays,
    purgedRows: purgedRows,
    embargoedRows: embargoedRows,
  );
}

double _weightedOf(
  List<WalkForwardFoldMetrics> folds,
  double Function(WalkForwardFoldMetrics fold) value,
) {
  var total = 0.0;
  var weight = 0;
  for (final fold in folds) {
    total += value(fold) * fold.samples;
    weight += fold.samples;
  }
  return weight == 0 ? 0 : total / weight;
}

extension on WalkForwardReport {
  double _weighted(double Function(WalkForwardFoldMetrics fold) value) =>
      _weightedOf(folds, value);
}
