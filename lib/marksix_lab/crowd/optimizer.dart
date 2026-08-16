import 'dart:math' as math;

import '../core/combinatorics.dart';
import '../core/drbg.dart';
import 'crowd_model.dart';

class RareCombination {
  const RareCombination({
    required this.numbers,
    required this.logPopularity,
    required this.rarityPercentile,
    required this.crowdRatio,
  });

  final List<int> numbers;
  final double logPopularity;
  final double rarityPercentile;
  final double crowdRatio;
}

/// Simulated annealing over `C(49,6)` minimising `q(c)`.
///
/// The moves are single-number swaps, which connect the whole space, so the
/// chain is irreducible; the acceptance rule is Metropolis with a geometric
/// cooling schedule. The search is seeded from the user's entropy so two people
/// asking for "the rarest ticket" do not receive the same one - otherwise the
/// advice would destroy itself by creating a new crowd.
class AntiCrowdOptimizer {
  AntiCrowdOptimizer(this.model, this.scale);

  final CrowdModel model;
  final RarityScale scale;

  List<RareCombination> search({
    required Drbg rng,
    int results = 5,
    int iterations = 6000,
    double startTemperature = 0.5,
    double endTemperature = 0.01,
    Set<int> excluded = const <int>{},
  }) {
    final found = <String, RareCombination>{};
    for (
      var attempt = 0;
      attempt < results * 3 && found.length < results;
      attempt++
    ) {
      final combo = _anneal(
        rng: rng,
        iterations: iterations,
        startTemperature: startTemperature,
        endTemperature: endTemperature,
        excluded: excluded,
      );
      final key = combo.join('-');
      if (found.containsKey(key)) continue;
      final score = model.logPopularity(combo);
      found[key] = RareCombination(
        numbers: combo,
        logPopularity: score,
        rarityPercentile: scale.percentileForScore(score),
        crowdRatio: scale.crowdRatio(score),
      );
    }
    final out = found.values.toList()
      ..sort((a, b) => a.logPopularity.compareTo(b.logPopularity));
    return out.take(results).toList();
  }

  List<int> _anneal({
    required Drbg rng,
    required int iterations,
    required double startTemperature,
    required double endTemperature,
    required Set<int> excluded,
  }) {
    final allowed = <int>[
      for (var n = 1; n <= kBallCount; n++)
        if (!excluded.contains(n)) n,
    ];
    if (allowed.length < kPickCount) {
      throw ArgumentError('too many numbers excluded');
    }

    var current = <int>[];
    final pool = List<int>.of(allowed);
    for (var i = 0; i < kPickCount; i++) {
      final j = i + rng.nextBelow(pool.length - i);
      final t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
      current.add(pool[i]);
    }
    current.sort();
    if (allowed.length == kPickCount) {
      // Only one feasible combination remains; annealing has nothing to explore.
      return current;
    }
    var currentScore = model.logPopularity(current);
    var best = List<int>.of(current);
    var bestScore = currentScore;

    final cooling = math.pow(endTemperature / startTemperature, 1 / iterations);
    var temperature = startTemperature;

    for (var step = 0; step < iterations; step++) {
      final candidate = List<int>.of(current);
      final replaceIndex = rng.nextBelow(kPickCount);
      final free = <int>[
        for (final n in allowed)
          if (!candidate.contains(n)) n,
      ];
      candidate[replaceIndex] = free[rng.nextBelow(free.length)];
      candidate.sort();

      final score = model.logPopularity(candidate);
      final delta = score - currentScore;
      if (delta <= 0 || rng.nextDouble() < math.exp(-delta / temperature)) {
        current = candidate;
        currentScore = score;
        if (score < bestScore) {
          bestScore = score;
          best = List<int>.of(candidate);
        }
      }
      temperature *= cooling;
    }
    return best;
  }
}
