import 'dart:math';

import '../models/shadow_forecast.dart';

/// Result of scoring the model against the market on the same settled matches.
class MarketBaselineVerdict {
  const MarketBaselineVerdict({
    required this.status,
    required this.message,
    required this.samples,
    required this.modelBrier,
    required this.marketBrier,
    required this.constantBrier,
    required this.confidence,
  });

  static const empty = MarketBaselineVerdict(
    status: 'insufficient',
    message: '未有已結算且同時存有盤口價的前瞻紀錄，暫不出推介。',
    samples: 0,
    modelBrier: 0,
    marketBrier: 0,
    constantBrier: 0,
    confidence: 0,
  );

  /// `insufficient`, `behind` or `ahead`.
  final String status;
  final String message;

  /// Settled forecasts carrying both a model probability and a market price.
  final int samples;
  final double modelBrier;

  /// Brier of the margin-free market probability of the same line.
  final double marketBrier;

  /// Brier of always quoting the settled base rate of the same matches.
  final double constantBrier;

  /// Weakest of the two paired t-statistics, market and constant.
  final double confidence;

  bool get beatsMarket => status == 'ahead';

  /// Recommendations are withheld until the model is shown to beat the market.
  ///
  /// Not beating the market is the default state, so an empty or short ledger
  /// suspends picks exactly like a losing one: the app never recommends on the
  /// strength of evidence it has not collected yet.
  bool get suspendPicks => !beatsMarket;
}

/// Minimum settled matches before the comparison is allowed to mean anything.
const marketBaselineMinimumSamples = 50;

/// One-sided ~95% threshold on the paired t-statistic of the Brier gain.
const marketBaselineMinimumT = 1.64;

/// Scores the model's stored probabilities against the market's on the same
/// settled matches.
///
/// Both sides are read from the same [ShadowForecast], so the model probability
/// was written down before kick-off and the market probability is the
/// margin-free price of the very line the model quoted. Nothing here is refit,
/// which is what makes the comparison out of sample.
MarketBaselineVerdict evaluateMarketBaseline(
  List<ShadowForecast> records, {
  int minimumSamples = marketBaselineMinimumSamples,
}) {
  final settled =
      records
          .where(
            (record) =>
                record.actualTotalCorners != null &&
                record.over9_5Probability != null &&
                record.marketOverProbability != null,
          )
          .toList()
        ..sort(
          (left, right) => (left.settledAt ?? left.matchDate).compareTo(
            right.settledAt ?? right.matchDate,
          ),
        );
  if (settled.length < minimumSamples) {
    return MarketBaselineVerdict(
      status: 'insufficient',
      message:
          '已結算並存有盤口價的前瞻紀錄 ${settled.length}／$minimumSamples 場，'
          '未夠比較，暫不出推介。',
      samples: settled.length,
      modelBrier: 0,
      marketBrier: 0,
      constantBrier: 0,
      confidence: 0,
    );
  }
  final labels = settled
      .map((record) => record.actualTotalCorners! > 9.5 ? 1.0 : 0.0)
      .toList(growable: false);
  final baseRate = labels.reduce((sum, value) => sum + value) / labels.length;
  final model = <double>[];
  final versusMarket = <double>[];
  final versusConstant = <double>[];
  var marketTotal = 0.0;
  var constantTotal = 0.0;
  for (var index = 0; index < settled.length; index++) {
    final label = labels[index];
    final own = pow(settled[index].over9_5Probability! - label, 2).toDouble();
    final market = pow(
      settled[index].marketOverProbability! - label,
      2,
    ).toDouble();
    final constant = pow(baseRate - label, 2).toDouble();
    model.add(own);
    versusMarket.add(market - own);
    versusConstant.add(constant - own);
    marketTotal += market;
    constantTotal += constant;
  }
  final count = settled.length;
  final modelBrier = model.reduce((sum, value) => sum + value) / count;
  final marketBrier = marketTotal / count;
  final constantBrier = constantTotal / count;
  final confidence = min(_pairedT(versusMarket), _pairedT(versusConstant));
  final ahead = confidence > marketBaselineMinimumT;
  return MarketBaselineVerdict(
    status: ahead ? 'ahead' : 'behind',
    message: ahead
        ? '$count 場已結算前瞻中，模型 Brier ${modelBrier.toStringAsFixed(4)} '
              '在統計上勝過盤口 ${marketBrier.toStringAsFixed(4)}，推介開放。'
        : '$count 場已結算前瞻中，模型 Brier ${modelBrier.toStringAsFixed(4)} '
              '未在統計上勝過盤口 ${marketBrier.toStringAsFixed(4)}，暫不出推介。',
    samples: count,
    modelBrier: modelBrier,
    marketBrier: marketBrier,
    constantBrier: constantBrier,
    confidence: confidence,
  );
}

/// Mean of [differences] divided by its own standard error.
///
/// A few dozen matches move a Brier score in the third decimal on their own, so
/// a smaller number is not yet an edge; zero is returned when the spread cannot
/// be estimated, which reads as no evidence.
double _pairedT(List<double> differences) {
  if (differences.length < 20) {
    return 0;
  }
  final mean =
      differences.reduce((sum, value) => sum + value) / differences.length;
  var variance = 0.0;
  for (final value in differences) {
    variance += pow(value - mean, 2);
  }
  variance /= differences.length - 1;
  final standardError = sqrt(variance / differences.length);
  return standardError <= 0 ? 0 : mean / standardError;
}
