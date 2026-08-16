/// Turns raw model scores into probabilities that match observed frequencies.
///
/// A model score only becomes a probability once it has been checked against
/// how often the event actually happened. Everything here is fitted on settled
/// outcomes of one market at a time, reports its own sample size, and falls back
/// to the identity map while the sample is too small to fit anything: an
/// unaudited score is never presented as a calibrated probability.
library;

import 'dart:math';

/// One settled observation: the probability that was published and what
/// happened.
class CalibrationSample {
  const CalibrationSample({
    required this.probability,
    required this.outcome,
    this.observedAt,
  });

  factory CalibrationSample.fromJson(Map<String, Object?> json) =>
      CalibrationSample(
        probability: (json['probability'] as num?)?.toDouble() ?? 0,
        outcome: json['outcome'] as bool? ?? false,
        observedAt: DateTime.tryParse(json['observedAt'] as String? ?? ''),
      );

  final double probability;
  final bool outcome;
  final DateTime? observedAt;

  bool get valid =>
      probability.isFinite && probability >= 0 && probability <= 1;

  Map<String, Object?> toJson() => {
    'probability': probability,
    'outcome': outcome,
    'observedAt': observedAt?.toUtc().toIso8601String(),
  };
}

/// Maps a raw model probability onto a calibrated probability.
abstract class ProbabilityCalibrator {
  const ProbabilityCalibrator();

  /// Short label naming the method, shown next to every calibrated number.
  String get label;

  /// `true` when the fit rests on enough settled outcomes to be trusted.
  bool get reliable;

  double apply(double probability);
}

/// Used until enough outcomes have settled: returns the score unchanged.
class IdentityCalibrator extends ProbabilityCalibrator {
  const IdentityCalibrator({this.samples = 0});

  final int samples;

  @override
  String get label => '未校準（樣本 $samples）';

  @override
  bool get reliable => false;

  @override
  double apply(double probability) => probability.clamp(0.0, 1.0);
}

/// Single-parameter temperature scaling in log-odds space.
///
/// Only sharpness is corrected, so it stays well behaved on small samples where
/// a free-form fit would simply memorise the noise.
class TemperatureCalibrator extends ProbabilityCalibrator {
  const TemperatureCalibrator({
    required this.temperature,
    required this.bias,
    required this.samples,
  });

  /// Values above one flatten the probabilities, below one sharpen them.
  final double temperature;
  final double bias;
  final int samples;

  @override
  String get label => '溫度校準 T=${temperature.toStringAsFixed(2)}（樣本 $samples）';

  @override
  bool get reliable => samples >= temperatureMinimumSamples;

  @override
  double apply(double probability) {
    final clamped = probability.clamp(1e-6, 1 - 1e-6);
    final logit = log(clamped / (1 - clamped));
    return 1 / (1 + exp(-(logit / temperature + bias)));
  }
}

/// Monotone step function fitted by pool-adjacent-violators.
///
/// Isotonic regression can correct any monotone distortion, which is what a
/// model that is systematically over-confident in one range needs, but it needs
/// a much larger sample than temperature scaling before it stops overfitting.
class IsotonicCalibrator extends ProbabilityCalibrator {
  const IsotonicCalibrator({
    required this.thresholds,
    required this.values,
    required this.samples,
  });

  /// Upper bound of each block, ascending.
  final List<double> thresholds;

  /// Calibrated probability of each block, non-decreasing.
  final List<double> values;
  final int samples;

  @override
  String get label => '等距回歸校準（$samples 個已結算樣本）';

  @override
  bool get reliable => samples >= isotonicMinimumSamples;

  @override
  double apply(double probability) {
    if (values.isEmpty) {
      return probability.clamp(0.0, 1.0);
    }
    for (var index = 0; index < thresholds.length; index++) {
      if (probability <= thresholds[index]) {
        return values[index];
      }
    }
    return values.last;
  }
}

/// Below this many settled outcomes nothing is fitted at all.
const temperatureMinimumSamples = 50;

/// Below this many settled outcomes isotonic regression overfits, so
/// temperature scaling is used instead.
const isotonicMinimumSamples = 200;

/// Number of equal-width bins used to report calibration error.
const calibrationBins = 10;

/// Scores of one calibration window, all computed on settled outcomes only.
class CalibrationReport {
  const CalibrationReport({
    required this.samples,
    required this.baseRate,
    required this.brier,
    required this.baselineBrier,
    required this.expectedCalibrationError,
    required this.maximumCalibrationError,
    required this.method,
    this.windowStart,
    this.windowEnd,
  });

  static const empty = CalibrationReport(
    samples: 0,
    baseRate: 0,
    brier: 0,
    baselineBrier: 0,
    expectedCalibrationError: 0,
    maximumCalibrationError: 0,
    method: '樣本不足',
  );

  final int samples;

  /// Observed frequency of the event; the always-predict-the-base-rate model.
  final double baseRate;
  final double brier;
  final double baselineBrier;
  final double expectedCalibrationError;
  final double maximumCalibrationError;
  final String method;
  final DateTime? windowStart;
  final DateTime? windowEnd;

  /// Fraction of the baseline Brier score removed; negative means the model is
  /// worse than simply predicting the base rate.
  double get brierSkill =>
      baselineBrier <= 0 ? 0 : (baselineBrier - brier) / baselineBrier;

  bool get reliable => samples >= temperatureMinimumSamples;

  /// Only a skill larger than the sampling noise of the estimate counts: with
  /// `n` outcomes the skill of a worthless model still wanders by roughly
  /// `1/sqrt(n)`, so anything smaller is indistinguishable from luck.
  bool get beatsBaseline =>
      reliable && brierSkill > 1 / sqrt(samples.toDouble());

  String get verdict {
    if (!reliable) {
      return '樣本不足（$samples／$temperatureMinimumSamples）：機率未經校準審核';
    }
    if (!beatsBaseline) {
      return '未顯著勝過基準率（Brier 技巧 '
          '${(brierSkill * 100).toStringAsFixed(1)}%）：不應視為有預測力';
    }
    return 'Brier 技巧 ${(brierSkill * 100).toStringAsFixed(1)}% · '
        'ECE ${(expectedCalibrationError * 100).toStringAsFixed(1)}%';
  }
}

/// Brier score of [samples], i.e. the mean squared probability error.
double brierScore(List<CalibrationSample> samples) {
  final valid = samples.where((sample) => sample.valid).toList();
  if (valid.isEmpty) {
    return 0;
  }
  var total = 0.0;
  for (final sample in valid) {
    final outcome = sample.outcome ? 1.0 : 0.0;
    total += pow(sample.probability - outcome, 2).toDouble();
  }
  return total / valid.length;
}

/// Expected and maximum calibration error over [calibrationBins] equal bins.
({double expected, double maximum}) calibrationError(
  List<CalibrationSample> samples,
) {
  final valid = samples.where((sample) => sample.valid).toList();
  if (valid.isEmpty) {
    return (expected: 0, maximum: 0);
  }
  final counts = List<int>.filled(calibrationBins, 0);
  final predicted = List<double>.filled(calibrationBins, 0);
  final observed = List<double>.filled(calibrationBins, 0);
  for (final sample in valid) {
    final index = min(
      (sample.probability * calibrationBins).floor(),
      calibrationBins - 1,
    );
    counts[index]++;
    predicted[index] += sample.probability;
    observed[index] += sample.outcome ? 1 : 0;
  }
  var expected = 0.0;
  var maximum = 0.0;
  for (var index = 0; index < calibrationBins; index++) {
    if (counts[index] == 0) {
      continue;
    }
    final gap =
        (observed[index] / counts[index] - predicted[index] / counts[index])
            .abs();
    expected += gap * counts[index] / valid.length;
    maximum = max(maximum, gap);
  }
  return (expected: expected, maximum: maximum);
}

/// Fits the strongest calibrator the sample size supports.
ProbabilityCalibrator fitCalibrator(List<CalibrationSample> samples) {
  final valid = samples.where((sample) => sample.valid).toList();
  if (valid.length < temperatureMinimumSamples) {
    return IdentityCalibrator(samples: valid.length);
  }
  if (valid.length >= isotonicMinimumSamples) {
    return _fitIsotonic(valid);
  }
  return _fitTemperature(valid);
}

/// Scores [samples] after mapping them through [calibrator].
CalibrationReport evaluateCalibration(
  List<CalibrationSample> samples, {
  ProbabilityCalibrator? calibrator,
}) {
  final valid = samples.where((sample) => sample.valid).toList()
    ..sort(_byObservedAt);
  if (valid.isEmpty) {
    return CalibrationReport.empty;
  }
  final fitted = calibrator ?? fitCalibrator(valid);
  final mapped = [
    for (final sample in valid)
      CalibrationSample(
        probability: fitted.apply(sample.probability),
        outcome: sample.outcome,
        observedAt: sample.observedAt,
      ),
  ];
  final baseRate =
      valid.where((sample) => sample.outcome).length / valid.length;
  final error = calibrationError(mapped);
  final times = valid
      .map((sample) => sample.observedAt)
      .whereType<DateTime>()
      .toList();
  return CalibrationReport(
    samples: valid.length,
    baseRate: baseRate,
    brier: brierScore(mapped),
    baselineBrier: baseRate * (1 - baseRate),
    expectedCalibrationError: error.expected,
    maximumCalibrationError: error.maximum,
    method: fitted.label,
    windowStart: times.isEmpty ? null : times.first,
    windowEnd: times.isEmpty ? null : times.last,
  );
}

/// Keeps the most recent [size] samples: calibration must follow the current
/// model and the current market, not the whole history.
List<CalibrationSample> rollingWindow(
  List<CalibrationSample> samples, {
  int size = 400,
}) {
  final ordered = samples.where((sample) => sample.valid).toList()
    ..sort(_byObservedAt);
  if (ordered.length <= size) {
    return ordered;
  }
  return ordered.sublist(ordered.length - size);
}

int _byObservedAt(CalibrationSample left, CalibrationSample right) {
  final leftTime = left.observedAt;
  final rightTime = right.observedAt;
  if (leftTime == null || rightTime == null) {
    return 0;
  }
  return leftTime.compareTo(rightTime);
}

TemperatureCalibrator _fitTemperature(List<CalibrationSample> samples) {
  var temperature = 1.0;
  var bias = 0.0;
  const steps = 400;
  const learningRate = 0.05;
  for (var step = 0; step < steps; step++) {
    var temperatureGradient = 0.0;
    var biasGradient = 0.0;
    for (final sample in samples) {
      final clamped = sample.probability.clamp(1e-6, 1 - 1e-6);
      final logit = log(clamped / (1 - clamped));
      final scaled = logit / temperature + bias;
      final predicted = 1 / (1 + exp(-scaled));
      final error = predicted - (sample.outcome ? 1.0 : 0.0);
      // d(scaled)/d(temperature) = -logit / temperature^2
      temperatureGradient += error * (-logit / (temperature * temperature));
      biasGradient += error;
    }
    final scale = 1 / samples.length;
    temperature = (temperature - learningRate * temperatureGradient * scale)
        .clamp(0.25, 6.0);
    bias -= learningRate * biasGradient * scale;
  }
  return TemperatureCalibrator(
    temperature: temperature,
    bias: bias,
    samples: samples.length,
  );
}

IsotonicCalibrator _fitIsotonic(List<CalibrationSample> samples) {
  final ordered = [...samples]
    ..sort((left, right) => left.probability.compareTo(right.probability));
  // Samples sharing a score are one block: their order carries no information.
  final values = <double>[];
  final weights = <double>[];
  final bounds = <double>[];
  for (final sample in ordered) {
    final outcome = sample.outcome ? 1.0 : 0.0;
    if (bounds.isNotEmpty && bounds.last == sample.probability) {
      final last = bounds.length - 1;
      final weight = weights[last] + 1;
      values[last] = (values[last] * weights[last] + outcome) / weight;
      weights[last] = weight;
      continue;
    }
    values.add(outcome);
    weights.add(1);
    bounds.add(sample.probability);
  }
  // Pool adjacent violators: merge any block whose mean breaks monotonicity.
  var index = 0;
  while (index < values.length - 1) {
    if (values[index] <= values[index + 1]) {
      index++;
      continue;
    }
    final totalWeight = weights[index] + weights[index + 1];
    final pooled =
        (values[index] * weights[index] +
            values[index + 1] * weights[index + 1]) /
        totalWeight;
    values[index] = pooled;
    weights[index] = totalWeight;
    bounds[index] = bounds[index + 1];
    values.removeAt(index + 1);
    weights.removeAt(index + 1);
    bounds.removeAt(index + 1);
    if (index > 0) {
      index--;
    }
  }
  return IsotonicCalibrator(
    thresholds: bounds,
    values: values,
    samples: samples.length,
  );
}
