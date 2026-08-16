import 'dart:math' as math;

import '../data/draw.dart';
import '../stats/distributions.dart';
import 'crowd_model.dart';

class CalibrationResult {
  const CalibrationResult({
    required this.intercept,
    required this.weights,
    required this.logLikelihood,
    required this.nullLogLikelihood,
    required this.observations,
    required this.iterations,
  });

  final double intercept;
  final Map<CrowdFeature, double> weights;
  final double logLikelihood;

  /// Log-likelihood of the constant-rate (uniform crowd) model.
  final double nullLogLikelihood;

  final int observations;
  final int iterations;

  /// Likelihood-ratio statistic against the uniform-crowd null.
  double get deviance => 2 * (logLikelihood - nullLogLikelihood);

  int get degreesOfFreedom => weights.length;

  double get pValue => chiSquareSf(deviance, degreesOfFreedom);
}

/// Fits `q(c)` from published first-division winner counts.
///
/// This is the inverse problem that makes the crowd model empirical rather than
/// speculative. The winning combination of each draw is, by construction, a
/// uniform random sample of the combination space, so regressing observed
/// winner counts on combination features gives an unbiased estimate of the
/// crowd's preference surface:
///
///   `y_i ~ Poisson(exp(a + w . f(c_i)))`
///
/// Fitted by gradient ascent on the Poisson log-likelihood with L2 shrinkage.
class CrowdCalibration {
  static CalibrationResult fit(
    List<Draw> draws, {
    double learningRate = 0.05,
    int maxIterations = 4000,
    double l2 = 1e-3,
    Map<CrowdFeature, double>? initialWeights,
  }) {
    final usable = draws
        .where((d) => d.isValid && d.jackpotWinners != null)
        .toList(growable: false);
    if (usable.length < 20) {
      throw ArgumentError(
        'need at least 20 draws with winner counts, got ${usable.length}',
      );
    }

    final baseModel = CrowdModel();
    final designs = usable
        .map((d) => baseModel.features(d.sorted))
        .toList(growable: false);
    final targets = usable
        .map((d) => d.jackpotWinners!)
        .toList(growable: false);

    final keys = CrowdFeature.values;
    final w = <CrowdFeature, double>{
      for (final k in keys) k: initialWeights?[k] ?? 0.0,
    };
    final meanY = targets.reduce((a, b) => a + b) / targets.length;
    var intercept = math.log(math.max(meanY, 1e-6));

    var iterations = 0;
    for (var it = 0; it < maxIterations; it++) {
      iterations = it + 1;
      var gIntercept = 0.0;
      final g = <CrowdFeature, double>{for (final k in keys) k: 0.0};

      for (var i = 0; i < designs.length; i++) {
        var eta = intercept;
        final f = designs[i];
        for (final k in keys) {
          eta += w[k]! * (f[k] ?? 0);
        }
        final mu = math.exp(eta.clamp(-30.0, 30.0));
        final residual = targets[i] - mu;
        gIntercept += residual;
        for (final k in keys) {
          g[k] = g[k]! + residual * (f[k] ?? 0);
        }
      }

      final n = designs.length;
      intercept += learningRate * gIntercept / n;
      var maxStep = (learningRate * gIntercept / n).abs();
      for (final k in keys) {
        final step = learningRate * (g[k]! / n - l2 * w[k]!);
        w[k] = w[k]! + step;
        maxStep = math.max(maxStep, step.abs());
      }
      if (maxStep < 1e-9) break;
    }

    double logLik(double a, Map<CrowdFeature, double> weights) {
      var ll = 0.0;
      for (var i = 0; i < designs.length; i++) {
        var eta = a;
        final f = designs[i];
        for (final k in keys) {
          eta += weights[k]! * (f[k] ?? 0);
        }
        final mu = math.exp(eta.clamp(-30.0, 30.0));
        ll += poissonLogPmf(targets[i].round(), mu);
      }
      return ll;
    }

    final nullLl = logLik(
      math.log(math.max(meanY, 1e-6)),
      <CrowdFeature, double>{for (final k in keys) k: 0.0},
    );

    return CalibrationResult(
      intercept: intercept,
      weights: w,
      logLikelihood: logLik(intercept, w),
      nullLogLikelihood: nullLl,
      observations: designs.length,
      iterations: iterations,
    );
  }
}
