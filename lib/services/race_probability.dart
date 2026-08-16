/// Race level probability structure.
///
/// A race is a single event where exactly one runner wins, so runner
/// probabilities are not independent events that happen to sum to one after a
/// division. This library builds them the way the outcome is generated:
///
/// * a conditional logit (softmax over runner utilities) for the win pool,
/// * a Henery generalised Harville expansion for the place pools,
/// * a de-vigged and favourite-longshot corrected public pool prior.
library;

import 'dart:math';

/// Softmax over runner utilities: the race level win probabilities of a
/// conditional logit / Plackett-Luce model.
List<double> conditionalLogit(List<double> utilities) {
  if (utilities.isEmpty) {
    return const [];
  }
  final peak = utilities.reduce(max);
  final weights = utilities
      .map((utility) => exp((utility - peak).clamp(-60.0, 60.0)))
      .toList();
  final total = weights.reduce((left, right) => left + right);
  if (total <= 0) {
    return List<double>.filled(utilities.length, 1 / utilities.length);
  }
  return weights.map((weight) => weight / total).toList();
}

/// Probability that each runner finishes inside the first [slots] places.
///
/// [henery] discounts the strength a runner carries into the later finishing
/// positions. `1.0` is the plain Harville model, which is known to overstate
/// how often a strong favourite fills a minor placing; an exponent below one
/// bends that back towards the field.
List<double> harvillePlaceProbabilities(
  List<double> win,
  int slots, {
  double henery = 1.0,
}) {
  if (win.isEmpty || slots <= 0) {
    return List<double>.filled(win.length, 0);
  }
  if (slots >= win.length) {
    return List<double>.filled(win.length, 1);
  }
  final place = List<double>.filled(win.length, 0);
  for (var target = 0; target < win.length; target++) {
    place[target] = _placeProbability(win, target, slots, henery);
  }
  return place;
}

double _placeProbability(
  List<double> win,
  int target,
  int slots,
  double henery,
) {
  final taken = <int>{};

  double walk(int depth) {
    final available = <int>[];
    for (var index = 0; index < win.length; index++) {
      if (!taken.contains(index)) {
        available.add(index);
      }
    }
    final weights = <int, double>{
      for (final index in available)
        index: pow(max(win[index], 1e-9), depth == 0 ? 1.0 : henery).toDouble(),
    };
    final total = weights.values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) {
      return 0;
    }
    final hit = (weights[target] ?? 0) / total;
    if (depth == slots - 1) {
      return hit;
    }
    var probability = hit;
    for (final index in available) {
      if (index == target) {
        continue;
      }
      final branch = weights[index]! / total;
      if (branch <= 0) {
        continue;
      }
      taken.add(index);
      probability += branch * walk(depth + 1);
      taken.remove(index);
    }
    return probability;
  }

  return walk(0).clamp(0.0, 1.0);
}

/// Number of runners the HKJC place pool pays, given the field size.
int placeSlotsForField(int fieldSize) {
  if (fieldSize >= 7) {
    return 3;
  }
  if (fieldSize >= 4) {
    return 2;
  }
  return 0;
}

/// The public pool implied probabilities with the takeout removed.
///
/// Returns an empty list when fewer than three runners are quoted, because a
/// partial pool cannot be normalised without inventing the missing runners.
List<double> poolProbabilities(List<double?> winOdds) {
  var quoted = 0;
  final raw = <double>[];
  for (final odds in winOdds) {
    if (odds != null && odds > 1) {
      quoted++;
      raw.add(1 / odds);
    } else {
      raw.add(0);
    }
  }
  if (quoted < 3 || quoted < winOdds.length - 1) {
    return const [];
  }
  final total = raw.reduce((left, right) => left + right);
  if (total <= 0) {
    return const [];
  }
  return raw.map((value) => value / total).toList();
}

/// Corrects the favourite-longshot bias of a parimutuel pool.
///
/// Punters systematically overbet long odds, so the de-vigged pool is a biased
/// estimate of the win frequency. Raising the pool probabilities to a power
/// above one and renormalising shifts that mass back onto the favourites; the
/// exponent is the single free parameter and stays close to one.
List<double> correctFavouriteLongshot(
  List<double> pool, {
  double exponent = 1.18,
}) {
  if (pool.isEmpty) {
    return const [];
  }
  final adjusted = pool
      .map((value) => pow(max(value, 1e-9), exponent).toDouble())
      .toList();
  final total = adjusted.reduce((left, right) => left + right);
  if (total <= 0) {
    return pool;
  }
  return adjusted.map((value) => value / total).toList();
}

/// Geometric (log space) blend of a model and a market distribution.
///
/// [marketWeight] `0` keeps the model untouched, `1` returns the market.
List<double> blendDistributions(
  List<double> model,
  List<double> market,
  double marketWeight,
) {
  if (market.length != model.length || market.isEmpty) {
    return model;
  }
  final weight = marketWeight.clamp(0.0, 1.0);
  if (weight == 0) {
    return model;
  }
  final blended = <double>[];
  for (var index = 0; index < model.length; index++) {
    blended.add(
      exp(
        (1 - weight) * log(max(model[index], 1e-9)) +
            weight * log(max(market[index], 1e-9)),
      ),
    );
  }
  final total = blended.reduce((left, right) => left + right);
  return blended.map((value) => value / total).toList();
}

/// Shannon entropy of a race, in bits, normalised by the entropy of a field
/// where every runner is equally likely.
///
/// `1` means the model separates nothing, `0` means it is certain.
double normalisedEntropy(List<double> probabilities) {
  if (probabilities.length < 2) {
    return 0;
  }
  var entropy = 0.0;
  for (final probability in probabilities) {
    if (probability > 0) {
      entropy -= probability * log(probability);
    }
  }
  return (entropy / log(probabilities.length)).clamp(0.0, 1.0);
}
