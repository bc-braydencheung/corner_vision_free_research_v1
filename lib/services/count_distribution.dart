import 'dart:math';

/// Negative binomial (NB2) count distribution used for corner totals.
///
/// Corner counts are more variable than a Poisson allows: match tempo, referee
/// interpretation and game state all move the rate within a single match, so
/// the realised variance sits above the mean. NB2 keeps the Poisson mean but
/// adds one dispersion parameter, `variance = mean * (1 + dispersion * mean)`,
/// and collapses back to the Poisson as `dispersion -> 0`.
class NegativeBinomialCount {
  const NegativeBinomialCount({required this.mean, required this.dispersion});

  /// Poisson-equivalent count distribution.
  const NegativeBinomialCount.poisson(this.mean) : dispersion = 0;

  final double mean;

  /// `alpha` in `Var = mu (1 + alpha mu)`; zero means equidispersed.
  final double dispersion;

  double get variance => mean * (1 + dispersion * mean);

  /// Ratio of the NB2 standard deviation to the Poisson one.
  double get overdispersionRatio => sqrt(1 + dispersion * mean);

  double pmf(int count) {
    if (count < 0) {
      return 0;
    }
    final mu = max(mean, 1e-6);
    if (dispersion <= 1e-9) {
      var logPmf = -mu + count * log(mu);
      for (var index = 2; index <= count; index++) {
        logPmf -= log(index);
      }
      return exp(logPmf);
    }
    final size = 1 / dispersion;
    final logProbability =
        logGamma(count + size) -
        logGamma(size) -
        logGamma(count + 1.0) +
        size * (log(size) - log(size + mu)) +
        count * (log(mu) - log(size + mu));
    return exp(logProbability);
  }

  /// `P(X <= count)`.
  double cdf(int count) {
    if (count < 0) {
      return 0;
    }
    var total = 0.0;
    for (var index = 0; index <= count; index++) {
      total += pmf(index);
    }
    return min(total, 1);
  }

  double survival(int count) => max(1 - cdf(count), 0);

  /// Probability mass over `0..maxCount`, renormalised to sum to one.
  List<double> masses({int maxCount = 30}) {
    final values = List<double>.filled(maxCount + 1, 0);
    var assigned = 0.0;
    for (var count = 0; count < maxCount; count++) {
      values[count] = pmf(count);
      assigned += values[count];
    }
    values[maxCount] = max(1 - assigned, 0);
    final total = values.fold(0.0, (sum, value) => sum + value);
    return [for (final value in values) value / total];
  }
}

/// Method-of-moments NB2 dispersion from observed counts and their predicted
/// means, floored at zero so an underdispersed sample never inflates variance.
///
/// `alpha = mean over i of ((y_i - mu_i)^2 - mu_i) / mu_i^2`.
double estimateDispersion(
  List<double> observed,
  List<double> predictedMeans, {
  int minimumSamples = 30,
}) {
  final count = min(observed.length, predictedMeans.length);
  if (count < minimumSamples) {
    return 0;
  }
  var total = 0.0;
  for (var index = 0; index < count; index++) {
    final mu = max(predictedMeans[index], 1e-3);
    final residual = observed[index] - mu;
    total += (residual * residual - mu) / (mu * mu);
  }
  return max(total / count, 0);
}

/// Lanczos approximation of `log Gamma(x)` for `x > 0`.
double logGamma(double x) {
  const coefficients = <double>[
    76.18009172947146,
    -86.50532032941677,
    24.01409824083091,
    -1.231739572450155,
    0.1208650973866179e-2,
    -0.5395239384953e-5,
  ];
  final value = max(x, 1e-12);
  var y = value;
  final tmp = value + 5.5;
  var series = 1.000000000190015;
  for (final coefficient in coefficients) {
    y += 1;
    series += coefficient / y;
  }
  return -tmp +
      (value + 0.5) * log(tmp) +
      log(2.5066282746310005 * series / value);
}
