import 'dart:math' as math;

import '../core/combinatorics.dart';
import '../core/drbg.dart';
import '../crowd/crowd_model.dart';
import 'draw.dart';

/// Generates a clearly-labelled synthetic draw history.
///
/// The app ships with no official data on purpose: pretending a bundled file is
/// the published record would be the same dishonesty as pretending to predict.
/// This generator instead serves two legitimate purposes:
///  * a demo dataset for the audit screens, and
///  * a controlled experiment: inject a known bias on one ball and see whether
///    the audit can detect it with the number of draws available. It usually
///    cannot, which is the lesson.
class SyntheticHistory {
  static List<Draw> generate({
    int draws = 1500,
    int seed = 0xC0FFEE,
    int? biasedBall,
    double relativeBias = 0.0,
    bool includeWinnerCounts = true,
    double unitsSold = 3.0e7,
    DateTime? startDate,
  }) {
    final rng = Drbg(<int>[
      seed & 0xff,
      (seed >> 8) & 0xff,
      (seed >> 16) & 0xff,
      0x5b,
    ]);
    final weights = List<double>.filled(kBallCount + 1, 1.0);
    if (biasedBall != null && biasedBall >= 1 && biasedBall <= kBallCount) {
      weights[biasedBall] = 1.0 + relativeBias;
    }

    final model = CrowdModel();
    final scale = buildRarityScale(model, samples: 4000, seed: seed ^ 0x1234);
    final start = startDate ?? DateTime(2015, 1, 6);
    final out = <Draw>[];
    var previous = const <int>[];

    for (var i = 0; i < draws; i++) {
      final picked = _weightedSubset(rng, weights);
      final combo = picked..sort();
      final crowdModel = CrowdModel(
        weights: model.weights,
        previousDraw: previous,
      );
      final ratio = scale.crowdRatio(crowdModel.logPopularity(combo));
      final lambda = unitsSold * ratio / kTotalCombinations;
      out.add(
        Draw(
          label: 'S${(i + 1).toString().padLeft(4, '0')}',
          date: start.add(Duration(days: 2 * i + (i % 3))),
          numbers: combo,
          extra: _extraNumber(rng, combo),
          jackpotWinners: includeWinnerCounts
              ? _poisson(rng, lambda).toDouble()
              : null,
        ),
      );
      previous = combo;
    }
    return out;
  }

  static List<int> _weightedSubset(Drbg rng, List<double> weights) {
    final remaining = List<int>.generate(kBallCount, (i) => i + 1);
    final w = List<double>.generate(kBallCount, (i) => weights[i + 1]);
    final picked = <int>[];
    for (var k = 0; k < kPickCount; k++) {
      final total = w.reduce((a, b) => a + b);
      var target = rng.nextDouble() * total;
      var index = 0;
      while (index < w.length - 1) {
        target -= w[index];
        if (target <= 0) break;
        index++;
      }
      picked.add(remaining[index]);
      remaining.removeAt(index);
      w.removeAt(index);
    }
    return picked;
  }

  static int _extraNumber(Drbg rng, List<int> combo) {
    while (true) {
      final v = 1 + rng.nextBelow(kBallCount);
      if (!combo.contains(v)) return v;
    }
  }

  static int _poisson(Drbg rng, double lambda) {
    if (lambda <= 0) return 0;
    if (lambda < 30) {
      final l = math.exp(-lambda);
      var k = 0;
      var p = 1.0;
      do {
        k++;
        p *= rng.nextDouble();
      } while (p > l);
      return k - 1;
    }
    return math.max(
      0,
      (lambda + math.sqrt(lambda) * rng.nextGaussian()).round(),
    );
  }
}
