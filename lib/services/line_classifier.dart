import 'dart:math';

import '../models/football_mobile.dart';
import 'football_mobile_engine.dart';

/// Corner lines the app quotes, and therefore the lines worth classifying.
const classifierLines = <double>[7.5, 8.5, 9.5, 10.5, 11.5, 12.5];

/// Logistic model of one corner line, with the scaling that calibrates it.
///
/// The count model reaches a line's probability by predicting a total and
/// reading a Poisson tail, which forces the whole distribution to be right to
/// get one line right. This models the line's outcome directly instead, and is
/// released for a line only when it beat that Poisson tail out of sample —
/// [adopted] records that verdict rather than an intention.
class LineProbabilityModel {
  const LineProbabilityModel({
    required this.line,
    required this.means,
    required this.scales,
    required this.weights,
    required this.intercept,
    required this.calibrationSlope,
    required this.calibrationShift,
    required this.samples,
    required this.brier,
    required this.baselineBrier,
    required this.constantBrier,
    required this.confidence,
    required this.adopted,
  });

  factory LineProbabilityModel.fromJson(Map<String, Object?> json) {
    List<double> values(String key) =>
        ((json[key] as List<Object?>?) ?? const [])
            .map((value) => (value as num).toDouble())
            .toList(growable: false);
    return LineProbabilityModel(
      line: (json['line'] as num).toDouble(),
      means: values('means'),
      scales: values('scales'),
      weights: values('weights'),
      intercept: (json['intercept'] as num).toDouble(),
      calibrationSlope: (json['calibrationSlope'] as num).toDouble(),
      calibrationShift: (json['calibrationShift'] as num).toDouble(),
      samples: (json['samples'] as num).toInt(),
      brier: (json['brier'] as num).toDouble(),
      baselineBrier: (json['baselineBrier'] as num).toDouble(),
      constantBrier: (json['constantBrier'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      adopted: json['adopted'] as bool,
    );
  }

  final double line;
  final List<double> means;
  final List<double> scales;
  final List<double> weights;
  final double intercept;

  /// Platt scaling of the raw log-odds, fitted on a window the weights never
  /// saw, so an overconfident classifier is flattened instead of trusted.
  final double calibrationSlope;
  final double calibrationShift;

  /// Rows the gate was measured on, and what it measured.
  final int samples;
  final double brier;
  final double baselineBrier;

  /// Score of always quoting the training base rate of this line.
  ///
  /// A classifier can beat the Poisson tail simply by having a better average,
  /// which says nothing about telling matches apart, so the constant is scored
  /// too and the gate requires beating both.
  final double constantBrier;

  /// Weakest of the two paired t-statistics behind [adopted].
  ///
  /// A hold-out of a few dozen matches moves the fourth decimal of a Brier
  /// score on its own, so the gate asks how large the improvement is next to
  /// its own standard error instead of just which number is smaller.
  final double confidence;
  final bool adopted;

  double get brierSkill =>
      baselineBrier <= 0 ? 0 : (baselineBrier - brier) / baselineBrier;

  /// Calibrated probability that the total goes over [line].
  double overProbability(List<double> features) {
    final logit = _rawLogit(features);
    return _sigmoid(calibrationSlope * logit + calibrationShift);
  }

  double _rawLogit(List<double> features) {
    var value = intercept;
    final columns = min(min(weights.length, means.length), features.length);
    for (var index = 0; index < columns; index++) {
      value +=
          weights[index] * (features[index] - means[index]) / scales[index];
    }
    return value.clamp(-12.0, 12.0);
  }

  Map<String, Object?> toJson() => {
    'line': line,
    'means': means,
    'scales': scales,
    'weights': weights,
    'intercept': intercept,
    'calibrationSlope': calibrationSlope,
    'calibrationShift': calibrationShift,
    'samples': samples,
    'brier': brier,
    'baselineBrier': baselineBrier,
    'constantBrier': constantBrier,
    'confidence': confidence,
    'adopted': adopted,
  };
}

/// Every line's classifier, including the ones the gate refused.
///
/// The refused ones are kept so the app can disclose that a line was tried and
/// lost, instead of silently looking as though it was never modelled.
class LineClassifierSet {
  const LineClassifierSet({required this.lines, this.note = ''});

  factory LineClassifierSet.fromJson(Map<String, Object?> json) =>
      LineClassifierSet(
        lines: ((json['lines'] as List<Object?>?) ?? const [])
            .map(
              (item) => LineProbabilityModel.fromJson(
                (item as Map).cast<String, Object?>(),
              ),
            )
            .toList(growable: false),
        note: json['note'] as String? ?? '',
      );

  static const empty = LineClassifierSet(lines: []);

  final List<LineProbabilityModel> lines;

  /// Why nothing was released, when nothing was.
  final String note;

  int get adoptedCount => lines.where((model) => model.adopted).length;

  /// The released classifier of [line], or null when the Poisson tail still
  /// owns that line.
  LineProbabilityModel? adoptedFor(double line) {
    for (final model in lines) {
      if (model.line == line && model.adopted) {
        return model;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'lines': lines.map((model) => model.toJson()).toList(),
    'note': note,
  };
}

/// Fits and gates one classifier per line.
///
/// The three windows are used for three different jobs and never swapped:
/// [development] fits the weights, [calibration] fits the Platt scaling, and
/// [holdout] only judges. The comparator is the same dynamic baseline the count
/// model is scored against, so "beat the baseline" means the same thing in both
/// reports.
///
/// A line with too few rows, or with one outcome missing from a window, is
/// returned unadopted rather than fitted on nothing.
LineClassifierSet trainLineClassifiers({
  required List<FootballTrainingRow> development,
  required List<FootballTrainingRow> calibration,
  required List<FootballTrainingRow> holdout,
  List<double> lines = classifierLines,
  int epochs = 220,
  double learningRate = 0.08,
  double l2 = 0.004,
}) {
  if (development.length < 80 ||
      calibration.length < 30 ||
      holdout.length < 30) {
    return const LineClassifierSet(lines: [], note: '樣本不足，未訓練分類模型');
  }
  final normalisation = _normalisation(development);
  final output = <LineProbabilityModel>[];
  for (final line in lines) {
    final labels = development.map((row) => _label(row, line)).toList();
    final positives = labels.where((label) => label > 0.5).length;
    if (positives < 20 || development.length - positives < 20) {
      // A line the history almost never crosses cannot be learned, and a
      // near-constant probability is exactly what the Poisson tail already
      // gives.
      continue;
    }
    var weights = List<double>.filled(FootballMobileEngine.featureCount, 0);
    var intercept = _logit(positives / development.length);
    for (var epoch = 0; epoch < epochs; epoch++) {
      (weights, intercept) = _epoch(
        rows: development,
        normalisation: normalisation,
        weights: weights,
        intercept: intercept,
        line: line,
        learningRate: learningRate,
        l2: l2,
      );
    }
    final scaling = _fitCalibration(
      rows: calibration,
      normalisation: normalisation,
      weights: weights,
      intercept: intercept,
      line: line,
    );
    final candidate = LineProbabilityModel(
      line: line,
      means: normalisation.means,
      scales: normalisation.scales,
      weights: weights,
      intercept: intercept,
      calibrationSlope: scaling.$1,
      calibrationShift: scaling.$2,
      samples: holdout.length,
      brier: 0,
      baselineBrier: 0,
      constantBrier: 0,
      confidence: 0,
      adopted: false,
    );
    final baseRate = positives / development.length;
    final own = <double>[];
    final versusBaseline = <double>[];
    final versusConstant = <double>[];
    for (final row in holdout) {
      final label = _label(row, line);
      final score = pow(
        candidate.overProbability(row.features) - label,
        2,
      ).toDouble();
      final baseline = pow(
        _poissonOver(row.baselineTotal, line) - label,
        2,
      ).toDouble();
      final constant = pow(baseRate - label, 2).toDouble();
      own.add(score);
      versusBaseline.add(baseline - score);
      versusConstant.add(constant - score);
    }
    final count = holdout.length;
    final baselineGain = _pairedT(versusBaseline);
    final constantGain = _pairedT(versusConstant);
    final confidence = min(baselineGain, constantGain);
    output.add(
      LineProbabilityModel(
        line: line,
        means: candidate.means,
        scales: candidate.scales,
        weights: candidate.weights,
        intercept: candidate.intercept,
        calibrationSlope: candidate.calibrationSlope,
        calibrationShift: candidate.calibrationShift,
        samples: count,
        brier: own.reduce((sum, value) => sum + value) / count,
        baselineBrier:
            (own.reduce((sum, value) => sum + value) +
                versusBaseline.reduce((sum, value) => sum + value)) /
            count,
        constantBrier:
            (own.reduce((sum, value) => sum + value) +
                versusConstant.reduce((sum, value) => sum + value)) /
            count,
        confidence: confidence,
        adopted: confidence > _minimumT,
      ),
    );
  }
  if (output.isEmpty) {
    return const LineClassifierSet(lines: [], note: '沒有一條盤口有足夠的兩邊樣本');
  }
  return LineClassifierSet(
    lines: output,
    note: output.any((model) => model.adopted)
        ? ''
        : '每條盤口的分類模型都未在統計上勝過基準，全部保留原本分佈',
  );
}

/// One-sided ~95% threshold on the paired t-statistic of the Brier gain.
const _minimumT = 1.64;

/// Mean of [differences] divided by its own standard error.
///
/// Zero when the spread cannot be estimated, which reads as "no evidence".
double _pairedT(List<double> differences) {
  if (differences.length < 20) {
    return 0;
  }
  final mean =
      differences.reduce((sum, value) => sum + value) / differences.length;
  var variance = 0.0;
  for (final value in differences) {
    variance += pow(value - mean, 2);
  }
  variance /= differences.length - 1;
  final standardError = sqrt(variance / differences.length);
  return standardError <= 0 ? 0 : mean / standardError;
}

double _label(FootballTrainingRow row, double line) =>
    row.totalCorners > line ? 1.0 : 0.0;

double _poissonOver(double mean, double line) =>
    FootballMobileEngine.poissonDistribution(
      mean,
    ).skip(line.floor() + 1).fold(0.0, (sum, value) => sum + value);

(List<double>, double) _epoch({
  required List<FootballTrainingRow> rows,
  required _Normalisation normalisation,
  required List<double> weights,
  required double intercept,
  required double line,
  required double learningRate,
  required double l2,
}) {
  final gradient = List<double>.filled(weights.length, 0);
  var interceptGradient = 0.0;
  for (final row in rows) {
    final features = normalisation.apply(row.features);
    var value = intercept;
    for (var index = 0; index < weights.length; index++) {
      value += weights[index] * features[index];
    }
    final error = _sigmoid(value) - _label(row, line);
    interceptGradient += error;
    for (var index = 0; index < weights.length; index++) {
      gradient[index] += error * features[index];
    }
  }
  final scale = 1 / max(rows.length, 1);
  final updated = List<double>.from(weights);
  for (var index = 0; index < updated.length; index++) {
    updated[index] -=
        learningRate * (gradient[index] * scale + l2 * updated[index]);
  }
  return (updated, intercept - learningRate * interceptGradient * scale);
}

/// Platt scaling of the raw log-odds, fitted on rows the weights never saw.
///
/// Returns the identity when the window carries only one outcome: there is
/// nothing to calibrate against, and a fitted slope would only be noise.
(double, double) _fitCalibration({
  required List<FootballTrainingRow> rows,
  required _Normalisation normalisation,
  required List<double> weights,
  required double intercept,
  required double line,
}) {
  final positives = rows.where((row) => _label(row, line) > 0.5).length;
  if (positives == 0 || positives == rows.length) {
    return (1, 0);
  }
  final logits = <double>[];
  final labels = <double>[];
  for (final row in rows) {
    final features = normalisation.apply(row.features);
    var value = intercept;
    for (var index = 0; index < weights.length; index++) {
      value += weights[index] * features[index];
    }
    logits.add(value.clamp(-12.0, 12.0));
    labels.add(_label(row, line));
  }
  var slope = 1.0;
  var shift = 0.0;
  for (var epoch = 0; epoch < 400; epoch++) {
    var slopeGradient = 0.0;
    var shiftGradient = 0.0;
    for (var index = 0; index < logits.length; index++) {
      final error = _sigmoid(slope * logits[index] + shift) - labels[index];
      slopeGradient += error * logits[index];
      shiftGradient += error;
    }
    final scale = 1 / logits.length;
    slope -= 0.05 * slopeGradient * scale;
    shift -= 0.05 * shiftGradient * scale;
  }
  // A negative slope would invert the classifier, which is a fitting failure
  // rather than a finding, so the raw model is kept instead.
  return slope <= 0 ? (1, 0) : (slope, shift);
}

_Normalisation _normalisation(List<FootballTrainingRow> rows) {
  final means = List<double>.filled(FootballMobileEngine.featureCount, 0);
  for (final row in rows) {
    for (var index = 0; index < means.length; index++) {
      means[index] += row.features[index];
    }
  }
  for (var index = 0; index < means.length; index++) {
    means[index] /= max(rows.length, 1);
  }
  final scales = List<double>.filled(means.length, 0);
  for (final row in rows) {
    for (var index = 0; index < scales.length; index++) {
      scales[index] += pow(row.features[index] - means[index], 2);
    }
  }
  for (var index = 0; index < scales.length; index++) {
    scales[index] = sqrt(scales[index] / max(rows.length, 1));
    if (scales[index] < 0.0001) {
      scales[index] = 1;
    }
  }
  return _Normalisation(means, scales);
}

class _Normalisation {
  const _Normalisation(this.means, this.scales);

  final List<double> means;
  final List<double> scales;

  List<double> apply(List<double> features) => [
    for (var index = 0; index < means.length; index++)
      index < features.length
          ? (features[index] - means[index]) / scales[index]
          : 0.0,
  ];
}

double _sigmoid(double value) => 1 / (1 + exp(-value.clamp(-30.0, 30.0)));

double _logit(double probability) {
  final bounded = probability.clamp(0.001, 0.999);
  return log(bounded / (1 - bounded));
}
