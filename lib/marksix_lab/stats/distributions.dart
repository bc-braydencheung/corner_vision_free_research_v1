import 'dart:math' as math;

import '../core/combinatorics.dart';

double _erf(double x) {
  final t = 1.0 / (1.0 + 0.5 * x.abs());
  final y =
      t *
      math.exp(
        -x * x -
            1.26551223 +
            t *
                (1.00002368 +
                    t *
                        (0.37409196 +
                            t *
                                (0.09678418 +
                                    t *
                                        (-0.18628806 +
                                            t *
                                                (0.27886807 +
                                                    t *
                                                        (-1.13520398 +
                                                            t *
                                                                (1.48851587 +
                                                                    t *
                                                                        (-0.82215223 +
                                                                            t * 0.17087277)))))))),
      );
  return x >= 0 ? 1.0 - y : y - 1.0;
}

double normalCdf(double z) => 0.5 * (1 + _erf(z / math.sqrt2));

double normalSf(double z) => 1 - normalCdf(z);

/// Two-sided normal tail probability.
double twoSidedNormalP(double z) => 2 * normalSf(z.abs());

/// Acklam's rational approximation to the standard normal quantile.
double normalQuantile(double p) {
  if (p <= 0 || p >= 1) {
    throw ArgumentError.value(p, 'p', 'must be in (0, 1)');
  }
  const a = <double>[
    -3.969683028665376e+01,
    2.209460984245205e+02,
    -2.759285104469687e+02,
    1.383577518672690e+02,
    -3.066479806614716e+01,
    2.506628277459239e+00,
  ];
  const b = <double>[
    -5.447609879822406e+01,
    1.615858368580409e+02,
    -1.556989798598866e+02,
    6.680131188771972e+01,
    -1.328068155288572e+01,
  ];
  const c = <double>[
    -7.784894002430293e-03,
    -3.223964580411365e-01,
    -2.400758277161838e+00,
    -2.549732539343734e+00,
    4.374664141464968e+00,
    2.938163982698783e+00,
  ];
  const d = <double>[
    7.784695709041462e-03,
    3.224671290700398e-01,
    2.445134137142996e+00,
    3.754408661907416e+00,
  ];
  const pLow = 0.02425;
  if (p < pLow) {
    final q = math.sqrt(-2 * math.log(p));
    return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
            c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  if (p > 1 - pLow) {
    final q = math.sqrt(-2 * math.log(1 - p));
    return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q +
            c[5]) /
        ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
  }
  final q = p - 0.5;
  final r = q * q;
  return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) *
      q /
      (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
}

/// Regularized lower incomplete gamma P(a, x).
double lowerRegularizedGamma(double a, double x) {
  if (x < 0 || a <= 0) throw ArgumentError('a > 0 and x >= 0 required');
  if (x == 0) return 0;
  if (x < a + 1) {
    var ap = a;
    var sum = 1.0 / a;
    var del = sum;
    for (var n = 0; n < 500; n++) {
      ap += 1;
      del *= x / ap;
      sum += del;
      if (del.abs() < sum.abs() * 1e-15) break;
    }
    return sum * math.exp(-x + a * math.log(x) - lnGamma(a));
  }
  return 1 - _upperGammaContinuedFraction(a, x);
}

double _upperGammaContinuedFraction(double a, double x) {
  const tiny = 1e-300;
  var b = x + 1 - a;
  var c = 1 / tiny;
  var d = 1 / b;
  var h = d;
  for (var i = 1; i < 500; i++) {
    final an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (d.abs() < tiny) d = tiny;
    c = b + an / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < 1e-15) break;
  }
  return math.exp(-x + a * math.log(x) - lnGamma(a)) * h;
}

/// Upper tail of the chi-square distribution with `df` degrees of freedom.
double chiSquareSf(double x, int df) {
  if (x <= 0) return 1;
  return 1 - lowerRegularizedGamma(df / 2, x / 2);
}

double _betaContinuedFraction(double a, double b, double x) {
  const tiny = 1e-300;
  final qab = a + b;
  final qap = a + 1;
  final qam = a - 1;
  var c = 1.0;
  var d = 1 - qab * x / qap;
  if (d.abs() < tiny) d = tiny;
  d = 1 / d;
  var h = d;
  for (var m = 1; m <= 300; m++) {
    final m2 = 2 * m;
    var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    h *= d * c;
    aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (d.abs() < tiny) d = tiny;
    c = 1 + aa / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < 1e-14) break;
  }
  return h;
}

/// Regularized incomplete beta I_x(a, b).
double regularizedIncompleteBeta(double a, double b, double x) {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  final front = math.exp(
    lnGamma(a + b) -
        lnGamma(a) -
        lnGamma(b) +
        a * math.log(x) +
        b * math.log(1 - x),
  );
  if (x < (a + 1) / (a + b + 2)) {
    return front * _betaContinuedFraction(a, b, x) / a;
  }
  return 1 -
      math.exp(
            lnGamma(a + b) -
                lnGamma(a) -
                lnGamma(b) +
                b * math.log(1 - x) +
                a * math.log(x),
          ) *
          _betaContinuedFraction(b, a, 1 - x) /
          b;
}

/// Quantile of Beta(a, b) by bisection on the regularized incomplete beta.
double betaQuantile(double a, double b, double p) {
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    if (regularizedIncompleteBeta(a, b, mid) < p) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Asymptotic Kolmogorov-Smirnov tail: Q(d * sqrt(n)).
double kolmogorovSf(double d, int n) {
  final lambda = (math.sqrt(n) + 0.12 + 0.11 / math.sqrt(n)) * d;
  if (lambda <= 0) return 1;
  var sum = 0.0;
  for (var j = 1; j <= 100; j++) {
    final term =
        2 * math.pow(-1, j - 1) * math.exp(-2 * j * j * lambda * lambda);
    sum += term;
    if (term.abs() < 1e-12) break;
  }
  return sum.clamp(0.0, 1.0);
}

double poissonLogPmf(int k, double lambda) {
  if (lambda <= 0) return k == 0 ? 0 : double.negativeInfinity;
  return k * math.log(lambda) - lambda - lnGamma(k + 1);
}
