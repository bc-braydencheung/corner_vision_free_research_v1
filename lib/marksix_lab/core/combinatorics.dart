import 'dart:math' as math;

const int kBallCount = 49;
const int kPickCount = 6;

/// Exact binomial coefficient for the sizes used here (fits in 2^53).
int binomial(int n, int k) {
  if (k < 0 || k > n) return 0;
  final kk = math.min(k, n - k);
  var result = 1;
  for (var i = 1; i <= kk; i++) {
    result = result * (n - kk + i) ~/ i;
  }
  return result;
}

double lnBinomial(int n, int k) {
  if (k < 0 || k > n) return double.negativeInfinity;
  return lnGamma(n + 1) - lnGamma(k + 1) - lnGamma(n - k + 1);
}

/// Lanczos approximation of ln Gamma(x), x > 0.
double lnGamma(double x) {
  const g = <double>[
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (x < 0.5) {
    return math.log(math.pi / math.sin(math.pi * x)) - lnGamma(1 - x);
  }
  final z = x - 1;
  var a = 0.99999999999980993;
  final t = z + 7.5;
  for (var i = 0; i < g.length; i++) {
    a += g[i] / (z + i + 1);
  }
  return 0.5 * math.log(2 * math.pi) +
      (z + 0.5) * math.log(t) -
      t +
      math.log(a);
}

/// Total number of Mark Six main-number combinations: C(49,6) = 13,983,816.
final int kTotalCombinations = binomial(kBallCount, kPickCount);

/// Shannon entropy of one uniform draw, in bits: log2 C(49,6) ~ 23.74.
final double kDrawEntropyBits = math.log(kTotalCombinations) / math.ln2;

/// Number of `k`-subsets of `1..n` containing no two consecutive integers:
/// C(n - k + 1, k). Used as the exact null for the adjacency test.
int nonAdjacentSubsetCount(int n, int k) => binomial(n - k + 1, k);
