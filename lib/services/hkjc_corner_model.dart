import 'dart:math';

import '../models/hkjc_football.dart';

/// Fair (vig-free) view of one hi/lo line plus the cross-line Poisson model.
///
/// Two independent numbers are produced for every line:
///
/// * [fairHighOdds] / [fairLowOdds] remove the bookmaker margin from the two
///   HKJC prices of that single line (`p = (1/o) / Σ(1/o)`). They say what the
///   quoted price would be at zero margin, nothing more.
/// * [modelHighOdds] / [modelLowOdds] come from one Poisson total-corner mean
///   fitted to *all* lines of the match at once, so a line that disagrees with
///   its neighbours shows up as a difference against the fair price.
class HkjcCornerLineAssessment {
  const HkjcCornerLineAssessment({
    required this.line,
    required this.marketHighProbability,
    required this.marketLowProbability,
    required this.overround,
    required this.modelHighProbability,
    required this.modelPushProbability,
    required this.modelHighEdge,
    required this.modelLowEdge,
  });

  final HkjcMarketLine line;

  /// Vig-free market probabilities implied by the pair of HKJC prices.
  final double marketHighProbability;
  final double marketLowProbability;

  /// `Σ(1/odds) - 1`; the margin HKJC charges on this line.
  final double overround;

  /// Poisson probability of the high side winning, push excluded.
  final double modelHighProbability;

  /// Probability the split line lands exactly on a half stake refund.
  final double modelPushProbability;

  /// Expected profit per unit stake at the quoted HKJC odds.
  final double modelHighEdge;
  final double modelLowEdge;

  double get modelLowProbability => 1 - modelHighProbability;

  double get fairHighOdds => _odds(marketHighProbability);
  double get fairLowOdds => _odds(marketLowProbability);
  double get modelHighOdds => _odds(modelHighProbability);
  double get modelLowOdds => _odds(modelLowProbability);

  static double _odds(double probability) => 1 / max(probability, 1e-4);
}

/// Whole-match corner assessment: fitted mean, per line detail, best edge.
class HkjcCornerAssessment {
  const HkjcCornerAssessment({
    required this.expectedCorners,
    required this.lines,
    required this.bestLine,
    required this.bestDirection,
    required this.bestEdge,
  });

  /// Poisson mean total corners implied jointly by every quoted line.
  final double expectedCorners;
  final List<HkjcCornerLineAssessment> lines;

  /// Line carrying the largest positive edge, if any line does.
  final HkjcCornerLineAssessment? bestLine;

  /// `high` or `low` for [bestLine].
  final String bestDirection;
  final double bestEdge;

  bool get hasEdge => bestLine != null && bestEdge > 0;
}

/// Win/push/loss split of one side of a hi/lo line.
class HkjcLineOutcome {
  const HkjcLineOutcome({
    required this.win,
    required this.push,
    required this.loss,
  });

  final double win;
  final double push;
  final double loss;

  /// Push-adjusted probability, so a quarter line compares to a `.5` line.
  double get adjusted => win + push / 2;

  double expectedValue(double odds) => win * (odds - 1) - loss;
}

/// Poisson total-corner model shared by every line of a match.
class HkjcCornerModel {
  const HkjcCornerModel({this.minimumEdge = 0.02});

  /// Edge below which no direction is suggested at all.
  final double minimumEdge;

  /// Removes the margin from a pair of hi/lo prices.
  ///
  /// Returns `null` when either side is missing or not a positive price.
  ({double high, double low, double overround})? removeVig(
    double? highOdds,
    double? lowOdds,
  ) {
    if (highOdds == null || lowOdds == null || highOdds <= 1 || lowOdds <= 1) {
      return null;
    }
    final rawHigh = 1 / highOdds;
    final rawLow = 1 / lowOdds;
    final total = rawHigh + rawLow;
    return (high: rawHigh / total, low: rawLow / total, overround: total - 1);
  }

  /// Win/push/loss of the high side of [line] under a Poisson([mean]) total.
  HkjcLineOutcome highOutcome(double mean, HkjcMarketLine line) {
    final components = line.components;
    var win = 0.0;
    var push = 0.0;
    var loss = 0.0;
    for (final component in components) {
      final integral = component == component.roundToDouble();
      final threshold = component.floor();
      final atLine = integral ? _poissonPmf(mean, threshold) : 0.0;
      final below = _poissonCdf(mean, integral ? threshold - 1 : threshold);
      win += 1 - below - atLine;
      push += atLine;
      loss += below;
    }
    final count = components.length;
    return HkjcLineOutcome(
      win: win / count,
      push: push / count,
      loss: loss / count,
    );
  }

  HkjcLineOutcome lowOutcome(double mean, HkjcMarketLine line) {
    final high = highOutcome(mean, line);
    return HkjcLineOutcome(win: high.loss, push: high.push, loss: high.win);
  }

  /// Solves for the Poisson mean whose high-side probabilities match the
  /// vig-free market probabilities of every quoted line.
  ///
  /// The residual sum is monotone increasing in the mean, so a bisection finds
  /// the unique moment-matching solution. Returns `null` without usable lines.
  double? fitExpectedCorners(List<HkjcMarketLine> lines) {
    final usable = <(HkjcMarketLine, double)>[];
    for (final line in lines) {
      if (line.status == 'SUSPENDED') {
        continue;
      }
      final fair = removeVig(line.highOdds, line.lowOdds);
      if (fair != null) {
        usable.add((line, fair.high));
      }
    }
    if (usable.isEmpty) {
      return null;
    }
    double residual(double mean) {
      var sum = 0.0;
      for (final entry in usable) {
        final weight = entry.$1.main ? 2.0 : 1.0;
        sum += weight * (highOutcome(mean, entry.$1).adjusted - entry.$2);
      }
      return sum;
    }

    var low = 0.5;
    var high = 30.0;
    if (residual(low) > 0) {
      return low;
    }
    if (residual(high) < 0) {
      return high;
    }
    for (var i = 0; i < 60; i++) {
      final mid = (low + high) / 2;
      if (residual(mid) < 0) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return (low + high) / 2;
  }

  /// Full assessment of the corner pool of one fixture.
  ///
  /// Returns `null` when HKJC has not opened a corner pool for the fixture, so
  /// the UI can say so instead of showing a zero line.
  HkjcCornerAssessment? assess(HkjcFootballFixture fixture) {
    final mean = fitExpectedCorners(fixture.cornerLines);
    if (mean == null) {
      return null;
    }
    final assessments = <HkjcCornerLineAssessment>[];
    HkjcCornerLineAssessment? bestLine;
    var bestDirection = '';
    var bestEdge = 0.0;
    for (final line in fixture.cornerLines) {
      final fair = removeVig(line.highOdds, line.lowOdds);
      if (fair == null) {
        continue;
      }
      final high = highOutcome(mean, line);
      final low = lowOutcome(mean, line);
      final highEdge = high.expectedValue(line.highOdds!);
      final lowEdge = low.expectedValue(line.lowOdds!);
      final assessment = HkjcCornerLineAssessment(
        line: line,
        marketHighProbability: fair.high,
        marketLowProbability: fair.low,
        overround: fair.overround,
        modelHighProbability: high.adjusted,
        modelPushProbability: high.push,
        modelHighEdge: highEdge,
        modelLowEdge: lowEdge,
      );
      assessments.add(assessment);
      if (line.status != 'AVAILABLE') {
        continue;
      }
      if (highEdge > bestEdge && highEdge >= minimumEdge) {
        bestEdge = highEdge;
        bestDirection = 'high';
        bestLine = assessment;
      }
      if (lowEdge > bestEdge && lowEdge >= minimumEdge) {
        bestEdge = lowEdge;
        bestDirection = 'low';
        bestLine = assessment;
      }
    }
    return HkjcCornerAssessment(
      expectedCorners: mean,
      lines: assessments,
      bestLine: bestLine,
      bestDirection: bestDirection,
      bestEdge: bestEdge,
    );
  }

  static double _poissonPmf(double mean, int count) {
    if (count < 0) {
      return 0;
    }
    var logPmf = -mean + count * log(mean);
    for (var i = 2; i <= count; i++) {
      logPmf -= log(i);
    }
    return exp(logPmf);
  }

  static double _poissonCdf(double mean, int count) {
    if (count < 0) {
      return 0;
    }
    var total = 0.0;
    for (var i = 0; i <= count; i++) {
      total += _poissonPmf(mean, i);
    }
    return min(total, 1);
  }
}
