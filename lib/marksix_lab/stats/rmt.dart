import 'dart:math' as math;

import '../core/combinatorics.dart';
import '../core/drbg.dart';
import '../data/draw.dart';
import 'distributions.dart';

/// Poisson (uncorrelated levels) spacing density: `P(s) = exp(-s)`.
double poissonSpacingPdf(double s) => math.exp(-s);

double poissonSpacingCdf(double s) => 1 - math.exp(-s);

/// Wigner surmise for the GOE ensemble: `P(s) = (pi s / 2) exp(-pi s^2 / 4)`.
/// `P(0) = 0` is level repulsion: neighbouring levels avoid each other.
double wignerSpacingPdf(double s) =>
    (math.pi * s / 2) * math.exp(-math.pi * s * s / 4);

double wignerSpacingCdf(double s) => 1 - math.exp(-math.pi * s * s / 4);

class RmtReport {
  const RmtReport({
    required this.spacings,
    required this.ksPoisson,
    required this.ksWigner,
    required this.ksPoissonP,
    required this.logBayesFactorWignerOverPoisson,
    required this.monteCarloPForBayesFactor,
    required this.meanSpacing,
    required this.varianceSpacing,
    required this.draws,
  });

  /// Normalised nearest-neighbour spacings of the drawn numbers.
  final List<double> spacings;

  final double ksPoisson;
  final double ksWigner;

  /// Monte Carlo calibrated tail probability of the Poisson KS statistic.
  final double ksPoissonP;

  /// `sum log P_Wigner(s) - sum log P_Poisson(s)`. Positive favours level
  /// repulsion, i.e. a structured rather than independent draw.
  final double logBayesFactorWignerOverPoisson;

  /// Fraction of fair simulated histories with a Bayes factor at least this
  /// large. This is the honest calibration: the discreteness of a 6-of-49 draw
  /// means the exact null is not literally Poisson, so the null must be
  /// simulated rather than assumed.
  final double monteCarloPForBayesFactor;

  final double meanSpacing;
  final double varianceSpacing;
  final int draws;

  bool get favoursRepulsion =>
      logBayesFactorWignerOverPoisson > 0 && monteCarloPForBayesFactor < 0.05;
}

/// Level-spacing analysis of Mark Six results, borrowed from random matrix
/// theory and quantum chaos.
///
/// Each draw is read as six occupied levels in a 49-level spectrum. If the balls
/// were released completely independently, the normalised gaps follow the
/// Poisson law `exp(-s)`. If releasing one ball perturbs the chamber and
/// suppresses its neighbours, the gaps acquire level repulsion and follow the
/// Wigner surmise. The two hypotheses are compared by likelihood ratio, with the
/// null distribution obtained by simulating fair draws.
class RmtAnalysis {
  static List<double> spacingsOf(List<int> numbers) {
    final sorted = List<int>.of(numbers)..sort();
    final gaps = <double>[];
    for (var i = 1; i < sorted.length; i++) {
      gaps.add((sorted[i] - sorted[i - 1]).toDouble());
    }
    return gaps;
  }

  static double _ks(List<double> sortedSample, double Function(double) cdf) {
    var d = 0.0;
    final n = sortedSample.length;
    for (var i = 0; i < n; i++) {
      final f = cdf(sortedSample[i]);
      d = math.max(d, math.max(((i + 1) / n - f).abs(), (f - i / n).abs()));
    }
    return d;
  }

  static double _logBayesFactor(List<double> spacings) {
    var lb = 0.0;
    for (final s in spacings) {
      final w = wignerSpacingPdf(s);
      final p = poissonSpacingPdf(s);
      if (w <= 0 || p <= 0) continue;
      lb += math.log(w) - math.log(p);
    }
    return lb;
  }

  static List<double> _normalised(List<Draw> draws) {
    final raw = <double>[];
    for (final d in draws) {
      raw.addAll(spacingsOf(d.numbers));
    }
    if (raw.isEmpty) return raw;
    final mean = raw.reduce((a, b) => a + b) / raw.length;
    return raw.map((g) => g / mean).toList();
  }

  static RmtReport run(
    List<Draw> draws, {
    int monteCarloSamples = 400,
    int seed = 0x7f3a,
  }) {
    final valid = draws.where((d) => d.isValid).toList(growable: false);
    if (valid.isEmpty) throw ArgumentError('no valid draws supplied');

    final spacings = _normalised(valid);
    final sorted = List<double>.of(spacings)..sort();
    final ksP = _ks(sorted, poissonSpacingCdf);
    final ksW = _ks(sorted, wignerSpacingCdf);
    final logBf = _logBayesFactor(spacings);

    final mean = spacings.reduce((a, b) => a + b) / spacings.length;
    var variance = 0.0;
    for (final s in spacings) {
      variance += math.pow(s - mean, 2).toDouble();
    }
    variance /= spacings.length;

    final rng = Drbg(<int>[seed & 0xff, (seed >> 8) & 0xff, 0x2c, 0x55]);
    var exceedBf = 0;
    var exceedKs = 0;
    for (var s = 0; s < monteCarloSamples; s++) {
      final simDraws = <Draw>[];
      for (var i = 0; i < valid.length; i++) {
        simDraws.add(
          Draw(
            label: 'sim',
            date: DateTime.fromMillisecondsSinceEpoch(0),
            numbers: rng.chooseSubset(kBallCount, kPickCount),
          ),
        );
      }
      final simSpacings = _normalised(simDraws);
      if (_logBayesFactor(simSpacings) >= logBf) exceedBf++;
      final simSorted = List<double>.of(simSpacings)..sort();
      if (_ks(simSorted, poissonSpacingCdf) >= ksP) exceedKs++;
    }

    return RmtReport(
      spacings: spacings,
      ksPoisson: ksP,
      ksWigner: ksW,
      ksPoissonP: (exceedKs + 1) / (monteCarloSamples + 1),
      logBayesFactorWignerOverPoisson: logBf,
      monteCarloPForBayesFactor: (exceedBf + 1) / (monteCarloSamples + 1),
      meanSpacing: mean,
      varianceSpacing: variance,
      draws: valid.length,
    );
  }

  /// Asymptotic KS p-value, kept for reference alongside the calibrated one.
  static double asymptoticKsP(double d, int n) => kolmogorovSf(d, n);
}
