import 'dart:math';

import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import 'bivariate_corner_model.dart';
import 'calibration_service.dart';
import 'corner_strength_model.dart';
import 'count_distribution.dart';
import 'market_anchor.dart';
import 'online_learning.dart';

/// Fair (vig-free) view of one hi/lo line plus the cross-line Poisson model.
///
/// Two independent numbers are produced for every line:
///
/// * [fairHighOdds] / [fairLowOdds] remove the bookmaker margin from the two
///   HKJC prices of that single line (`p = (1/o) / Σ(1/o)`). They say what the
///   quoted price would be at zero margin, nothing more.
/// * [modelHighOdds] / [modelLowOdds] come from one negative-binomial
///   total-corner mean fitted to *all* lines of the match at once and blended
///   with the team-strength prior, so a line that disagrees with its
///   neighbours shows up as a difference against the fair price.
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

/// Model pick for one fixture together with how much the model trusts it.
///
/// [confidence] is deliberately not a win probability: it blends how large the
/// edge is, how well every quoted line agrees with the single fitted Poisson
/// mean, how many lines constrain that fit, and how much margin HKJC charges.
class HkjcCornerRecommendation {
  const HkjcCornerRecommendation({
    required this.line,
    required this.direction,
    required this.odds,
    required this.edge,
    required this.winProbability,
    required this.confidence,
  });

  final HkjcCornerLineAssessment line;

  /// `high` or `low`.
  final String direction;

  /// HKJC price of the recommended side.
  final double odds;

  /// Expected profit per unit stake at [odds].
  final double edge;
  final double winProbability;

  /// `0..1` trust score; see the class comment for what feeds it.
  final double confidence;

  String get directionLabel => direction == 'high' ? '大' : '細';

  String get confidenceLabel {
    if (confidence >= 0.6) {
      return '高';
    }
    if (confidence >= 0.4) {
      return '中';
    }
    return '低';
  }

  /// Quarter-Kelly stake fraction, a research-side sizing reference only.
  double get stakeFraction {
    final profit = odds - 1;
    if (profit <= 0) {
      return 0;
    }
    return max(0, min(0.05, edge / profit / 4));
  }
}

/// Whole-match corner assessment: fitted mean, per line detail, best edge.
class HkjcCornerAssessment {
  const HkjcCornerAssessment({
    required this.expectedCorners,
    required this.lines,
    required this.bestLine,
    required this.bestDirection,
    required this.bestEdge,
    required this.lineDispersion,
    required this.averageOverround,
    required this.recommendation,
    this.observation,
    this.marketExpectedCorners = 0,
    this.priorExpectedCorners,
    this.priorWeight = 0,
    this.dispersion = 0,
    this.weatherNote,
    this.jointNote,
    this.jointCorrelation,
    this.modelTrust = 1,
    this.drifting = false,
  });

  /// Blended NB2 mean total corners actually used for every probability.
  final double expectedCorners;

  /// Mean implied jointly by every quoted line, before the model prior.
  final double marketExpectedCorners;

  /// Mean from the team strength model, when both teams are known.
  final double? priorExpectedCorners;

  /// Share of the blended log mean contributed by [priorExpectedCorners].
  final double priorWeight;

  /// NB2 dispersion in force; `0` means the count model is Poisson.
  final double dispersion;

  /// Free kick-off forecast summary, when a venue coordinate is known.
  final String? weatherNote;

  /// Measured home/away corner correlation summary of this league, when fitted.
  final String? jointNote;

  /// Measured correlation itself, only when enough matches back it.
  final double? jointCorrelation;

  /// Share of the model's disagreement with the market that survived the online
  /// learner; `1` means the model is shown in full.
  final double modelTrust;

  /// Whether the online drift detectors are currently alarming.
  final bool drifting;
  final List<HkjcCornerLineAssessment> lines;

  /// Line carrying the largest positive edge, if any line does.
  final HkjcCornerLineAssessment? bestLine;

  /// `high` or `low` for [bestLine].
  final String bestDirection;
  final double bestEdge;

  /// RMS gap between model and vig-free market probabilities over all lines;
  /// a small value means the quoted lines are mutually consistent.
  final double lineDispersion;
  final double averageOverround;

  /// Pick worth showing, or `null` when no side clears the minimum edge.
  final HkjcCornerRecommendation? recommendation;

  /// Best-scoring side even when it does not clear the minimum edge.
  ///
  /// Kept separate from [recommendation] so a fixture the model declines still
  /// exposes its probability and confidence instead of rendering nothing.
  final HkjcCornerRecommendation? observation;

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

/// Negative-binomial total-corner model shared by every line of a match.
class HkjcCornerModel {
  const HkjcCornerModel({
    this.minimumEdge = 0.02,
    this.calibration,
    this.prior,
    this.weather,
    this.online,
    this.anchor,
    this.joint,
  });

  /// Effective variance of the market's own log mean.
  ///
  /// The HKJC corner line is sharp, so the model prior only moves the blended
  /// mean when its own posterior variance is comparable to this.
  static const marketLogVariance = 0.006;

  /// Edge below which no direction is suggested at all.
  final double minimumEdge;

  /// Team-strength prior for this fixture, when both teams are known.
  final CornerMeanPrior? prior;

  /// Free Open-Meteo forecast for the kick-off hour, when the venue is known.
  final FootballWeatherSnapshot? weather;

  /// Extra count variance carried by the weather.
  ///
  /// Rain and wind make a match scrappier without moving the corner mean in a
  /// direction the free data can pin down, so the forecast is allowed to widen
  /// the distribution and never to shift it. The cap keeps the effect smaller
  /// than the dispersion a league's own residuals justify.
  double get weatherDispersion {
    final forecast = weather;
    if (forecast == null) {
      return 0;
    }
    final rain = forecast.precipitationProbability.clamp(0.0, 1.0);
    final wind = (forecast.windSpeedKmh / 45).clamp(0.0, 1.0);
    return 0.018 * rain + 0.014 * wind;
  }

  /// Human readable summary of the forecast used, when present.
  String? get weatherNote {
    final forecast = weather;
    if (forecast == null) {
      return null;
    }
    return '開賽天氣 ${forecast.temperatureC.toStringAsFixed(0)}°C · '
        '降雨 ${(forecast.precipitationProbability * 100).round()}% · '
        '風 ${forecast.windSpeedKmh.toStringAsFixed(0)}km/h';
  }

  /// Measured home/away corner covariance of this league, when fitted.
  ///
  /// Modelling the total alone assumes the two counts are independent. The
  /// measured joint variance replaces that assumption, and only widens the
  /// total distribution: it never moves the mean, which stays anchored on the
  /// market and the strength prior.
  final BivariateCornerFit? joint;

  /// Extra dispersion implied by the measured home/away corner covariance.
  double jointDispersion(double mean) => joint?.dispersionFor(mean) ?? 0;

  /// NB2 dispersion in force: the wider of the fitted league dispersion and the
  /// weather driven floor.
  double get dispersion =>
      max(prior?.reliable == true ? prior!.dispersion : 0.0, weatherDispersion);

  /// Dispersion in force for a total of [mean], covariance included.
  double dispersionAt(double mean) => max(dispersion, jointDispersion(mean));

  /// Online learning state of the corner market, when it has been replayed.
  ///
  /// It decides how much of the model's disagreement with the market survives:
  /// a model that has not been beating its own fallback online has its
  /// disagreement shrunk towards the vig-free price rather than shown in full.
  final OnlineLearningState? online;

  /// Hedge-learned share of the model's disagreement with the price that is
  /// allowed to survive, when it has been measured.
  ///
  /// Before it is measured this is the documented conservative default, so the
  /// blend never rests on an unmeasured constant pretending to be a finding.
  final MarketAnchorState? anchor;

  /// Weight the model's own view keeps, from `0` to `1`.
  ///
  /// Two independent brakes multiply: how much the online learner still trusts
  /// the model at all, and how far the settled record says the model may move
  /// away from the market price.
  double get modelTrust {
    final state = online;
    final learned = anchor?.share ?? defaultMarketAnchor;
    if (state == null || state.settledSamples < 30) {
      return learned;
    }
    if (state.drifting) {
      return min(0.35, learned);
    }
    return (learned * (0.35 + 0.65 * state.modelWeight)).clamp(0.0, 1.0);
  }

  /// Corner-market calibration fitted on settled outcomes.
  ///
  /// When it is absent, or still resting on too few settled matches, the raw
  /// Poisson probability is shown unchanged and the confidence score is capped:
  /// an unaudited model must not present itself as a trustworthy one.
  final MarketCalibration? calibration;

  /// Re-splits an outcome so its push-adjusted probability is the calibrated
  /// one, leaving the push (stake refund) share untouched.
  HkjcLineOutcome _calibratedOutcome(HkjcLineOutcome outcome) {
    final mapped = calibration?.apply(outcome.adjusted);
    return mapped == null ? outcome : _withAdjusted(outcome, mapped);
  }

  /// Pulls the model probability towards the vig-free market probability by
  /// whatever trust the online learner has left in the model.
  HkjcLineOutcome _shrunkOutcome(HkjcLineOutcome outcome, double market) {
    final trust = modelTrust;
    if (trust >= 1) {
      return outcome;
    }
    return _withAdjusted(outcome, market + trust * (outcome.adjusted - market));
  }

  /// Same push share, but the decisive mass re-split so the push-adjusted
  /// probability equals [target].
  HkjcLineOutcome _withAdjusted(HkjcLineOutcome outcome, double target) {
    final decisive = outcome.win + outcome.loss;
    if (decisive <= 0) {
      return outcome;
    }
    final winShare = ((target - outcome.push / 2) / decisive).clamp(0.0, 1.0);
    return HkjcLineOutcome(
      win: winShare * decisive,
      push: outcome.push,
      loss: (1 - winShare) * decisive,
    );
  }

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

  /// Inverse-variance blend of the market mean with the team-strength prior.
  ///
  /// Both means are combined in log space, so the result stays positive and the
  /// blend is scale free. An unreliable prior is ignored outright.
  double blendedMean(double marketMean) {
    final candidate = prior;
    if (candidate == null || !candidate.reliable || candidate.totalMean <= 0) {
      return marketMean;
    }
    final weight = priorWeight;
    return exp(
      (1 - weight) * log(marketMean) + weight * log(candidate.totalMean),
    );
  }

  /// Share of the blended log mean taken from the prior.
  double get priorWeight {
    final candidate = prior;
    if (candidate == null || !candidate.reliable) {
      return 0;
    }
    final priorPrecision = 1 / max(candidate.logVariance, 1e-6);
    final marketPrecision = 1 / marketLogVariance;
    // The anchor is applied once, on the probability itself, so the mean blend
    // stays a plain inverse-variance combination.
    return priorPrecision / (priorPrecision + marketPrecision);
  }

  /// Win/push/loss of the high side of [line] under an NB2([mean]) total.
  HkjcLineOutcome highOutcome(double mean, HkjcMarketLine line) {
    final counts = NegativeBinomialCount(
      mean: mean,
      dispersion: dispersionAt(mean),
    );
    final components = line.components;
    var win = 0.0;
    var push = 0.0;
    var loss = 0.0;
    for (final component in components) {
      final integral = component == component.roundToDouble();
      final threshold = component.floor();
      final atLine = integral ? counts.pmf(threshold) : 0.0;
      final below = counts.cdf(integral ? threshold - 1 : threshold);
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
    final marketMean = fitExpectedCorners(fixture.cornerLines);
    if (marketMean == null) {
      return null;
    }
    final mean = blendedMean(marketMean);
    final assessments = <HkjcCornerLineAssessment>[];
    HkjcCornerLineAssessment? bestLine;
    var bestDirection = '';
    var bestEdge = 0.0;
    HkjcCornerLineAssessment? watchLine;
    var watchDirection = '';
    var watchEdge = double.negativeInfinity;
    for (final line in fixture.cornerLines) {
      final fair = removeVig(line.highOdds, line.lowOdds);
      if (fair == null) {
        continue;
      }
      final high = _shrunkOutcome(
        _calibratedOutcome(highOutcome(mean, line)),
        fair.high,
      );
      final low = HkjcLineOutcome(
        win: high.loss,
        push: high.push,
        loss: high.win,
      );
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
      if (highEdge > watchEdge) {
        watchEdge = highEdge;
        watchDirection = 'high';
        watchLine = assessment;
      }
      if (lowEdge > watchEdge) {
        watchEdge = lowEdge;
        watchDirection = 'low';
        watchLine = assessment;
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
    final lineGap = _dispersion(assessments);
    final overround = assessments.isEmpty
        ? 0.0
        : assessments.map((item) => item.overround).reduce((a, b) => a + b) /
              assessments.length;
    return HkjcCornerAssessment(
      expectedCorners: mean,
      marketExpectedCorners: marketMean,
      priorExpectedCorners: prior?.reliable == true ? prior!.totalMean : null,
      priorWeight: priorWeight,
      dispersion: dispersionAt(mean),
      jointNote: joint?.note,
      jointCorrelation: joint?.reliable == true ? joint!.correlation : null,
      weatherNote: weatherNote,
      modelTrust: modelTrust,
      drifting: online?.drifting ?? false,
      lines: assessments,
      bestLine: bestLine,
      bestDirection: bestDirection,
      bestEdge: bestEdge,
      lineDispersion: lineGap,
      averageOverround: overround,
      recommendation: bestLine == null
          ? null
          : _recommend(
              line: bestLine,
              direction: bestDirection,
              edge: bestEdge,
              lineCount: assessments.length,
              dispersion: lineGap,
              overround: overround,
              priorAgrees: _priorAgrees(bestDirection, marketMean),
            ),
      observation: watchLine == null
          ? null
          : _recommend(
              line: watchLine,
              direction: watchDirection,
              edge: watchEdge,
              lineCount: assessments.length,
              dispersion: lineGap,
              overround: overround,
              priorAgrees: _priorAgrees(watchDirection, marketMean),
            ),
    );
  }

  HkjcCornerRecommendation _recommend({
    required HkjcCornerLineAssessment line,
    required String direction,
    required double edge,
    required int lineCount,
    required double dispersion,
    required double overround,
    required bool priorAgrees,
  }) {
    final high = direction == 'high';
    final edgeScore = _unit(edge / 0.10);
    final agreementScore = _unit(1 - dispersion / 0.05);
    final depthScore = _unit((lineCount - 1) / 3);
    final marginScore = _unit(1 - overround / 0.10);
    final priorScore = priorAgrees ? 1.0 : 0.0;
    final rawConfidence =
        0.40 * edgeScore +
        0.22 * agreementScore +
        0.13 * depthScore +
        0.13 * marginScore +
        0.12 * priorScore;
    final audited = calibration?.report.beatsBaseline ?? false;
    final drifting = online?.drifting ?? false;
    final confidence = drifting
        ? min(rawConfidence, 0.30)
        : audited
        ? rawConfidence
        : min(rawConfidence, 0.39);
    return HkjcCornerRecommendation(
      line: line,
      direction: direction,
      odds: high ? line.line.highOdds! : line.line.lowOdds!,
      edge: edge,
      winProbability: high
          ? line.modelHighProbability
          : line.modelLowProbability,
      confidence: confidence,
    );
  }

  /// Whether the independent team-strength prior leans the same way as the pick.
  bool _priorAgrees(String direction, double marketMean) {
    final candidate = prior;
    if (candidate == null || !candidate.reliable) {
      return false;
    }
    final gap = candidate.totalMean - marketMean;
    return direction == 'high' ? gap > 0.15 : gap < -0.15;
  }

  static double _unit(double value) => value.clamp(0.0, 1.0);

  static double _dispersion(List<HkjcCornerLineAssessment> lines) {
    if (lines.isEmpty) {
      return 0;
    }
    var total = 0.0;
    for (final line in lines) {
      final gap = line.modelHighProbability - line.marketHighProbability;
      total += gap * gap;
    }
    return sqrt(total / lines.length);
  }
}
