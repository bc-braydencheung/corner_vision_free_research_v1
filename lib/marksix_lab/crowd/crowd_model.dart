import 'dart:math' as math;

import '../core/combinatorics.dart';
import '../core/drbg.dart';

/// Feature basis for the crowd's choice distribution `q(c)`.
///
/// Mark Six is parimutuel: the prize is split between winning units, so
/// `E[payout | c] = Pool * P(win) / (1 + N q(c))`. `P(win)` is identical for
/// every combination - physics guarantees that and no app can change it - but
/// `q(c)` varies by orders of magnitude because human choices are not uniform.
/// Minimising `q(c)` is the only lever that provably improves the outcome.
///
/// The crowd is modelled as a Boltzmann distribution over an energy of cultural
/// attraction: `q(c) = exp(w . f(c)) / Z`.
enum CrowdFeature {
  birthdayNumbers,
  monthNumbers,
  luckyNumbers,
  unluckyNumbers,
  consecutiveRun,
  arithmeticProgression,
  multiplesOfFive,
  sameLastDigit,
  sumCentrality,
  gridLineConcentration,
  evenGapSpread,
  repeatFromLastDraw,
}

const Set<int> kLuckyNumbers = <int>{3, 6, 8, 9, 18, 28, 38, 48};
const Set<int> kUnluckyNumbers = <int>{4, 14, 24, 34, 44};

/// Hand-set prior weights, in units of log-popularity. They encode documented
/// lottery-player biases (birthday dates dominate, 4 is avoided in Chinese
/// markets, patterns on the bet slip are over-picked) and are replaced by
/// [CrowdCalibration] output once winner-count data is supplied.
const Map<CrowdFeature, double> kDefaultCrowdWeights = <CrowdFeature, double>{
  CrowdFeature.birthdayNumbers: 0.34,
  CrowdFeature.monthNumbers: 0.10,
  CrowdFeature.luckyNumbers: 0.22,
  CrowdFeature.unluckyNumbers: -0.30,
  CrowdFeature.consecutiveRun: 0.18,
  CrowdFeature.arithmeticProgression: 1.10,
  CrowdFeature.multiplesOfFive: 0.09,
  CrowdFeature.sameLastDigit: 0.16,
  CrowdFeature.sumCentrality: 0.55,
  CrowdFeature.gridLineConcentration: 0.42,
  CrowdFeature.evenGapSpread: 0.25,
  CrowdFeature.repeatFromLastDraw: 0.14,
};

class CrowdModel {
  CrowdModel({
    Map<CrowdFeature, double>? weights,
    this.intercept = 0,
    this.previousDraw = const <int>[],
  }) : weights = <CrowdFeature, double>{...kDefaultCrowdWeights, ...?weights};

  final Map<CrowdFeature, double> weights;
  final double intercept;
  final List<int> previousDraw;

  static const int gridColumns = 7;

  Map<CrowdFeature, double> features(List<int> combo) {
    final c = List<int>.of(combo)..sort();
    final n = c.length;

    final birthday = c.where((v) => v <= 31).length / n;
    final month = c.where((v) => v <= 12).length / n;
    final lucky = c.where(kLuckyNumbers.contains).length / n;
    final unlucky = c.where(kUnluckyNumbers.contains).length / n;
    final fives = c.where((v) => v % 5 == 0).length / n;

    var longestRun = 1;
    var run = 1;
    for (var i = 1; i < n; i++) {
      if (c[i] == c[i - 1] + 1) {
        run++;
        longestRun = math.max(longestRun, run);
      } else {
        run = 1;
      }
    }

    var isAp = true;
    final step = c[1] - c[0];
    for (var i = 2; i < n; i++) {
      if (c[i] - c[i - 1] != step) {
        isAp = false;
        break;
      }
    }

    final digitCounts = <int, int>{};
    for (final v in c) {
      digitCounts[v % 10] = (digitCounts[v % 10] ?? 0) + 1;
    }
    final maxSameDigit = digitCounts.values.reduce(math.max) / n;

    final sum = c.reduce((a, b) => a + b);
    const meanSum = kPickCount * (kBallCount + 1) / 2;
    const sumSigma = 32.0;
    final sumCentral = math.exp(
      -math.pow(sum - meanSum, 2) / (2 * sumSigma * sumSigma),
    );

    final rows = <int, int>{};
    final cols = <int, int>{};
    for (final v in c) {
      rows[(v - 1) ~/ gridColumns] = (rows[(v - 1) ~/ gridColumns] ?? 0) + 1;
      cols[(v - 1) % gridColumns] = (cols[(v - 1) % gridColumns] ?? 0) + 1;
    }
    final lineConcentration =
        math.max(rows.values.reduce(math.max), cols.values.reduce(math.max)) /
        n;

    final gaps = <int>[];
    for (var i = 1; i < n; i++) {
      gaps.add(c[i] - c[i - 1]);
    }
    final meanGap = gaps.reduce((a, b) => a + b) / gaps.length;
    var gapVar = 0.0;
    for (final g in gaps) {
      gapVar += math.pow(g - meanGap, 2).toDouble();
    }
    gapVar /= gaps.length;
    final evenSpread = math.exp(-gapVar / 25);

    final repeats = previousDraw.isEmpty
        ? 0.0
        : c.where(previousDraw.contains).length / n;

    return <CrowdFeature, double>{
      CrowdFeature.birthdayNumbers: birthday,
      CrowdFeature.monthNumbers: month,
      CrowdFeature.luckyNumbers: lucky,
      CrowdFeature.unluckyNumbers: unlucky,
      CrowdFeature.consecutiveRun: (longestRun - 1) / (n - 1),
      CrowdFeature.arithmeticProgression: isAp ? 1.0 : 0.0,
      CrowdFeature.multiplesOfFive: fives,
      CrowdFeature.sameLastDigit: maxSameDigit,
      CrowdFeature.sumCentrality: sumCentral,
      CrowdFeature.gridLineConcentration: lineConcentration,
      CrowdFeature.evenGapSpread: evenSpread,
      CrowdFeature.repeatFromLastDraw: repeats,
    };
  }

  /// `w . f(c) + intercept`: unnormalised log-popularity.
  double logPopularity(List<int> combo) {
    final f = features(combo);
    var s = intercept;
    for (final entry in f.entries) {
      s += (weights[entry.key] ?? 0) * entry.value;
    }
    return s;
  }
}

class RarityScale {
  const RarityScale(this._sortedScores, this._logMeanExp);

  final List<double> _sortedScores;
  final double _logMeanExp;

  /// Fraction of random combinations that are *less* popular than [score].
  /// Low percentile = you are in the crowd; high percentile = you are alone.
  double percentileForScore(double score) {
    var lo = 0;
    var hi = _sortedScores.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sortedScores[mid] < score) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return 1.0 - lo / _sortedScores.length;
  }

  double get medianScore => _sortedScores[_sortedScores.length ~/ 2];

  /// `q(c)` normalised over all C(49,6) combinations, using a Monte Carlo
  /// estimate of `log Z`.
  double probability(double score) =>
      math.exp(score - _logMeanExp) / kTotalCombinations;

  /// How many times more or less often the crowd picks this combination than an
  /// average one.
  double crowdRatio(double score) => math.exp(score - _logMeanExp);
}

/// Monte Carlo normalisation of the crowd model over the full combination space.
RarityScale buildRarityScale(
  CrowdModel model, {
  int samples = 20000,
  int seed = 0x9e37,
}) {
  final rng = Drbg(<int>[seed & 0xff, (seed >> 8) & 0xff, 0x42, 0x7f]);
  final scores = <double>[];
  var maxScore = double.negativeInfinity;
  for (var i = 0; i < samples; i++) {
    final combo = rng.chooseSubset(kBallCount, kPickCount);
    final s = model.logPopularity(combo);
    scores.add(s);
    maxScore = math.max(maxScore, s);
  }
  var sumExp = 0.0;
  for (final s in scores) {
    sumExp += math.exp(s - maxScore);
  }
  final logMeanExp = maxScore + math.log(sumExp / scores.length);
  scores.sort();
  return RarityScale(scores, logMeanExp);
}
