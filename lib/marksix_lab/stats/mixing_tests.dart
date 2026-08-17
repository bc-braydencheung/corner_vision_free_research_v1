import 'dart:math' as math;

import '../core/combinatorics.dart';
import '../core/drbg.dart';
import '../data/draw.dart';
import 'distributions.dart';

class AdjacencyTest {
  const AdjacencyTest({
    required this.draws,
    required this.observedWithAdjacent,
    required this.expectedProbability,
    required this.zScore,
    required this.pValue,
  });

  final int draws;
  final int observedWithAdjacent;

  /// Exact null: `1 - C(44,6)/C(49,6)`.
  final double expectedProbability;
  final double zScore;
  final double pValue;
}

class LoadingOrderAutocorrelation {
  const LoadingOrderAutocorrelation({
    required this.lag,
    required this.correlation,
    required this.zScore,
    required this.pValue,
  });

  /// Separation in loading order (numbers are loaded into the machine in
  /// numerical order, so lag is distance along that order).
  final int lag;

  final double correlation;
  final double zScore;
  final double pValue;
}

class MixingReport {
  const MixingReport({
    required this.adjacency,
    required this.autocorrelations,
    required this.familywiseP,
  });

  final AdjacencyTest adjacency;
  final List<LoadingOrderAutocorrelation> autocorrelations;

  /// Bonferroni-corrected smallest p-value across the autocorrelation lags.
  final double familywiseP;

  bool get anyResidualStructure =>
      familywiseP < 0.05 || adjacency.pValue < 0.05;
}

/// Tests for residual memory of the machine's ordered initial condition.
///
/// The balls are loaded in numerical order, so their initial arrangement has
/// zero entropy. If the stirring time were shorter than the mixing time of the
/// induced random walk on permutations, the residual bias would not appear as
/// "hot numbers" - it would appear as structure in *loading-order distance*:
/// excess adjacency, or non-zero autocorrelation `C(k)` of the occupancy
/// indicator at lag `k`.
///
/// That is a different hypothesis from anything the frequency-based apps test,
/// and it is falsifiable, which is the point.
class MixingTests {
  static MixingReport run(
    List<Draw> draws, {
    int maxLag = 12,
    int monteCarloSamples = 1000,
    int seed = 0x4d2,
  }) {
    final valid = draws.where((d) => d.isValid).toList(growable: false);
    if (valid.isEmpty) throw ArgumentError('no valid draws supplied');

    final pNoAdjacent =
        nonAdjacentSubsetCount(kBallCount, kPickCount) / kTotalCombinations;
    final pAdjacent = 1 - pNoAdjacent;
    var withAdjacent = 0;
    for (final d in valid) {
      final s = d.sorted;
      for (var i = 1; i < s.length; i++) {
        if (s[i] == s[i - 1] + 1) {
          withAdjacent++;
          break;
        }
      }
    }
    final nDraws = valid.length;
    final sd = math.sqrt(nDraws * pAdjacent * (1 - pAdjacent));
    final z = sd == 0 ? 0.0 : (withAdjacent - nDraws * pAdjacent) / sd;

    final occupancy = valid
        .map(
          (d) =>
              List<bool>.generate(kBallCount, (i) => d.numbers.contains(i + 1)),
        )
        .toList(growable: false);

    double correlationAtLag(List<List<bool>> data, int lag) {
      var sum = 0.0;
      for (final row in data) {
        var hits = 0;
        for (var n = 0; n < kBallCount; n++) {
          if (row[n] && row[(n + lag) % kBallCount]) hits++;
        }
        sum += hits / kBallCount;
      }
      final mean = sum / data.length;
      const p = kPickCount / kBallCount;
      return mean - p * p;
    }

    final rng = Drbg(<int>[seed & 0xff, (seed >> 8) & 0xff, 0x71, 0x0e]);
    final simCorrelations = List<List<double>>.generate(
      maxLag,
      (_) => <double>[],
    );
    for (var s = 0; s < monteCarloSamples; s++) {
      final sim = <List<bool>>[];
      for (var i = 0; i < nDraws; i++) {
        final picked = rng.chooseSubset(kBallCount, kPickCount).toSet();
        sim.add(List<bool>.generate(kBallCount, (i) => picked.contains(i + 1)));
      }
      for (var lag = 1; lag <= maxLag; lag++) {
        simCorrelations[lag - 1].add(correlationAtLag(sim, lag));
      }
    }

    final results = <LoadingOrderAutocorrelation>[];
    var minP = 1.0;
    for (var lag = 1; lag <= maxLag; lag++) {
      final c = correlationAtLag(occupancy, lag);
      final sims = simCorrelations[lag - 1];
      final mean = sims.reduce((a, b) => a + b) / sims.length;
      var variance = 0.0;
      for (final v in sims) {
        variance += math.pow(v - mean, 2).toDouble();
      }
      variance /= sims.length;
      final sdSim = math.sqrt(variance);
      final zLag = sdSim == 0 ? 0.0 : (c - mean) / sdSim;
      final p = twoSidedNormalP(zLag);
      minP = math.min(minP, p);
      results.add(
        LoadingOrderAutocorrelation(
          lag: lag,
          correlation: c,
          zScore: zLag,
          pValue: p,
        ),
      );
    }

    return MixingReport(
      adjacency: AdjacencyTest(
        draws: nDraws,
        observedWithAdjacent: withAdjacent,
        expectedProbability: pAdjacent,
        zScore: z,
        pValue: twoSidedNormalP(z),
      ),
      autocorrelations: results,
      familywiseP: (minP * maxLag).clamp(0.0, 1.0),
    );
  }

  /// Mixing time of a random walk on `S_n` from the spectral gap:
  /// `t_mix ~ (ln(1/eps) + 0.5 ln n!) / (-ln|lambda_2|)`.
  ///
  /// This is the Bayer-Diaconis shuffle bound applied to a ball machine: with
  /// `lambda_2` estimated from the measured Lyapunov exponent as
  /// `exp(-lambda * dt)`, it says how many seconds of stirring are needed before
  /// the loading order is forgotten.
  static double mixingTimeFromSpectralGap({
    required double secondEigenvalue,
    int n = kBallCount,
    double epsilon = 0.01,
  }) {
    if (secondEigenvalue <= 0 || secondEigenvalue >= 1) {
      throw ArgumentError.value(
        secondEigenvalue,
        'secondEigenvalue',
        'must be in (0, 1)',
      );
    }
    final lnFactorial = lnGamma(n + 1);
    return (math.log(1 / epsilon) + 0.5 * lnFactorial) /
        -math.log(secondEigenvalue);
  }
}
