import 'dart:math' as math;

import '../core/combinatorics.dart';
import '../core/drbg.dart';
import '../data/draw.dart';
import 'distributions.dart';

class BallPosterior {
  const BallPosterior({
    required this.number,
    required this.count,
    required this.posteriorMean,
    required this.lower95,
    required this.upper95,
    required this.zScore,
  });

  final int number;
  final int count;
  final double posteriorMean;
  final double lower95;
  final double upper95;

  /// Standardised deviation from the uniform rate `1/49`.
  final double zScore;

  /// Relative deviation from uniform, e.g. 0.05 means "5% hotter".
  double get relativeDeviation => posteriorMean * kBallCount - 1;
}

class BiasAuditReport {
  const BiasAuditReport({
    required this.draws,
    required this.observations,
    required this.posteriors,
    required this.chiSquare,
    required this.chiSquareP,
    required this.monteCarloP,
    required this.klDivergence,
    required this.log10SanovBound,
    required this.extreme,
    required this.bonferroniP,
  });

  final int draws;
  final int observations;
  final List<BallPosterior> posteriors;
  final double chiSquare;

  /// Asymptotic p-value with 48 degrees of freedom.
  final double chiSquareP;

  /// Monte Carlo p-value under exact without-replacement sampling. Preferred,
  /// because the six balls of a draw are negatively correlated and the
  /// asymptotic chi-square null is only approximate.
  final double monteCarloP;

  final double klDivergence;

  /// `log10 exp(-n * KL)`: Sanov's exponential bound on observing a deviation at
  /// least this large under a fair machine.
  final double log10SanovBound;

  final BallPosterior extreme;

  /// Bonferroni-corrected p-value for the most extreme of the 49 balls.
  final double bonferroniP;

  bool get significantAtFivePercent => monteCarloP < 0.05;
}

/// Bayesian and large-deviation audit of ball frequencies.
///
/// This does not predict anything. It asks the only empirically answerable
/// question about the machine: is the outcome distribution uniform? A
/// Dirichlet(alpha) prior with a multinomial likelihood gives Beta marginals per
/// ball; chi-square and Sanov's theorem bound how surprising the observed
/// deviation is under a fair machine.
class BiasAudit {
  static BiasAuditReport run(
    List<Draw> draws, {
    double priorAlpha = 1.0,
    int monteCarloSamples = 2000,
    int seed = 0x1a2b,
  }) {
    final valid = draws.where((d) => d.isValid).toList(growable: false);
    if (valid.isEmpty) {
      throw ArgumentError('no valid draws supplied');
    }
    final counts = List<int>.filled(kBallCount + 1, 0);
    for (final d in valid) {
      for (final n in d.numbers) {
        counts[n]++;
      }
    }
    final n = valid.length * kPickCount;
    final expected = n / kBallCount;
    final priorTotal = priorAlpha * kBallCount;

    final posteriors = <BallPosterior>[];
    var chi = 0.0;
    var kl = 0.0;
    for (var b = 1; b <= kBallCount; b++) {
      final x = counts[b];
      chi += math.pow(x - expected, 2) / expected;
      if (x > 0) {
        final p = x / n;
        kl += p * math.log(p * kBallCount);
      }
      final a = priorAlpha + x;
      final bb = priorTotal - priorAlpha + n - x;
      final mean = a / (a + bb);
      final sd = math.sqrt(expected * (1 - 1 / kBallCount)) / n;
      posteriors.add(
        BallPosterior(
          number: b,
          count: x,
          posteriorMean: mean,
          lower95: betaQuantile(a, bb, 0.025),
          upper95: betaQuantile(a, bb, 0.975),
          zScore: sd == 0 ? 0 : (x / n - 1 / kBallCount) / sd,
        ),
      );
    }

    final rng = Drbg(<int>[seed & 0xff, (seed >> 8) & 0xff, 0x33, 0x91]);
    var exceed = 0;
    for (var s = 0; s < monteCarloSamples; s++) {
      final simCounts = List<int>.filled(kBallCount + 1, 0);
      for (var d = 0; d < valid.length; d++) {
        for (final v in rng.chooseSubset(kBallCount, kPickCount)) {
          simCounts[v]++;
        }
      }
      var simChi = 0.0;
      for (var b = 1; b <= kBallCount; b++) {
        simChi += math.pow(simCounts[b] - expected, 2) / expected;
      }
      if (simChi >= chi) exceed++;
    }

    final extreme = posteriors.reduce(
      (a, b) => a.zScore.abs() >= b.zScore.abs() ? a : b,
    );

    return BiasAuditReport(
      draws: valid.length,
      observations: n,
      posteriors: posteriors,
      chiSquare: chi,
      chiSquareP: chiSquareSf(chi, kBallCount - 1),
      monteCarloP: (exceed + 1) / (monteCarloSamples + 1),
      klDivergence: kl,
      log10SanovBound: -n * kl / math.ln10,
      extreme: extreme,
      bonferroniP: (twoSidedNormalP(extreme.zScore) * kBallCount).clamp(
        0.0,
        1.0,
      ),
    );
  }
}
