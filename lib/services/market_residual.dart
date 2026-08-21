/// Learns the model's deviation from the HKJC price instead of a price of its
/// own.
///
/// The count model produces a probability without ever looking at the quote,
/// and the anchor then decides how much of the disagreement survives. That
/// treats every disagreement as equally informative. Here the disagreement
/// itself is the input: the market's vig-free probability is the offset, and a
/// two-parameter correction learns how much of the model's gap against the
/// price is worth acting on, and in which direction.
///
/// Because the whole point is beating the price rather than predicting the
/// count, the fit is only adopted when it beats the price itself on a
/// chronological holdout it never trained on. Otherwise the price stands.
library;

import 'dart:math';

/// Minimum settled matches with a usable quote before a fit may be adopted.
const minimumResidualSamples = 60;

/// Share of the ordered samples kept as the untouched holdout.
const residualHoldoutShare = 0.3;

/// Largest log-odds disagreement the correction is allowed to read.
///
/// A quote of 1.05 against a model probability of 0.5 is a data problem, not a
/// signal, and without a cap a handful of them would dominate the fit.
const residualGapCap = 2.0;

double _logit(double probability) {
  final bounded = probability.clamp(1e-6, 1 - 1e-6);
  return log(bounded / (1 - bounded));
}

double _sigmoid(double value) => 1 / (1 + exp(-value));

/// One settled match seen as a deviation from the quote.
class MarketResidualObservation {
  const MarketResidualObservation({
    required this.settledAt,
    required this.outcome,
    required this.modelProbability,
    required this.marketProbability,
  });

  final DateTime settledAt;
  final bool outcome;

  /// Model probability of the same event, before any market correction.
  final double modelProbability;

  /// Vig-free market probability at capture time; never a closing price, so
  /// nothing the forecast could not have seen enters the fit.
  final double marketProbability;

  bool get usable =>
      modelProbability.isFinite &&
      marketProbability.isFinite &&
      modelProbability > 0 &&
      modelProbability < 1 &&
      marketProbability > 0 &&
      marketProbability < 1;

  /// Model's disagreement with the price, in log-odds and capped.
  double get gap => (_logit(modelProbability) - _logit(marketProbability))
      .clamp(-residualGapCap, residualGapCap);
}

/// Learned correction plus everything needed to audit it.
class MarketResidualState {
  const MarketResidualState({
    required this.bias,
    required this.gapWeight,
    required this.samples,
    required this.holdout,
    required this.brier,
    required this.marketBrier,
    required this.logLoss,
    required this.marketLogLoss,
    required this.adopted,
    required this.note,
    this.updatedAt,
  });

  static const initial = MarketResidualState(
    bias: 0,
    gapWeight: 0,
    samples: 0,
    holdout: 0,
    brier: 0,
    marketBrier: 0,
    logLoss: 0,
    marketLogLoss: 0,
    adopted: false,
    note: '尚未有足夠帶市場價的已結算樣本，偏離模型未啟用，機率維持原有處理。',
  );

  factory MarketResidualState.fromJson(Map<String, Object?> json) =>
      MarketResidualState(
        bias: (json['bias'] as num).toDouble(),
        gapWeight: (json['gapWeight'] as num).toDouble(),
        samples: (json['samples'] as num).toInt(),
        holdout: (json['holdout'] as num).toInt(),
        brier: (json['brier'] as num).toDouble(),
        marketBrier: (json['marketBrier'] as num).toDouble(),
        logLoss: (json['logLoss'] as num).toDouble(),
        marketLogLoss: (json['marketLogLoss'] as num).toDouble(),
        adopted: json['adopted'] as bool? ?? false,
        note: json['note'] as String? ?? '',
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
      );

  /// Constant log-odds shift against the price.
  final double bias;

  /// Share of the model's log-odds disagreement that is acted on.
  final double gapWeight;

  /// Usable settled matches seen, development plus holdout.
  final int samples;

  /// Matches in the chronological holdout the fit never trained on.
  final int holdout;

  /// Holdout scores of the correction and of the raw price, side by side.
  final double brier;
  final double marketBrier;
  final double logLoss;
  final double marketLogLoss;

  /// Whether the correction beat the price out of sample and is in force.
  final bool adopted;
  final String note;
  final DateTime? updatedAt;

  /// Corrected probability of the event, given the quote and the model.
  ///
  /// Returns the market probability untouched while the fit is not adopted, so
  /// an unproven correction can never move a displayed number.
  double predict({required double market, required double model}) {
    if (!adopted) {
      return market.clamp(0.0, 1.0);
    }
    final gap = (_logit(model) - _logit(market)).clamp(
      -residualGapCap,
      residualGapCap,
    );
    return _sigmoid(_logit(market) + bias + gapWeight * gap).clamp(0.0, 1.0);
  }

  /// How much of the market-beating claim is actually measured.
  bool get beatsMarket => adopted && brier < marketBrier;

  Map<String, Object?> toJson() => {
    'bias': bias,
    'gapWeight': gapWeight,
    'samples': samples,
    'holdout': holdout,
    'brier': brier,
    'marketBrier': marketBrier,
    'logLoss': logLoss,
    'marketLogLoss': marketLogLoss,
    'adopted': adopted,
    'note': note,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}

/// Fits [MarketResidualState] on settled matches, market price as the offset.
class MarketResidualLearner {
  const MarketResidualLearner({
    this.iterations = 400,
    this.learningRate = 0.08,
    this.ridge = 0.05,
  });

  final int iterations;
  final double learningRate;

  /// L2 penalty; with a two-parameter fit on tens of matches it is what keeps
  /// the correction from reading noise as an edge.
  final double ridge;

  MarketResidualState fit(List<MarketResidualObservation> observations) {
    final ordered =
        observations.where((observation) => observation.usable).toList()
          ..sort((left, right) => left.settledAt.compareTo(right.settledAt));
    if (ordered.length < minimumResidualSamples) {
      return MarketResidualState(
        bias: 0,
        gapWeight: 0,
        samples: ordered.length,
        holdout: 0,
        brier: 0,
        marketBrier: 0,
        logLoss: 0,
        marketLogLoss: 0,
        adopted: false,
        note:
            '只有 ${ordered.length} 筆帶市場價的已結算樣本（需 $minimumResidualSamples '
            '筆），偏離模型未啟用。',
        updatedAt: ordered.isEmpty ? null : ordered.last.settledAt,
      );
    }

    final split = max(1, (ordered.length * (1 - residualHoldoutShare)).floor());
    final development = ordered.sublist(0, split);
    final holdout = ordered.sublist(split);

    var bias = 0.0;
    var gapWeight = 0.0;
    for (var step = 0; step < iterations; step++) {
      var biasGradient = 0.0;
      var gapGradient = 0.0;
      for (final observation in development) {
        final gap = observation.gap;
        final predicted = _sigmoid(
          _logit(observation.marketProbability) + bias + gapWeight * gap,
        );
        final error = predicted - (observation.outcome ? 1.0 : 0.0);
        biasGradient += error;
        gapGradient += error * gap;
      }
      final size = development.length;
      bias -= learningRate * (biasGradient / size + ridge * bias);
      gapWeight -= learningRate * (gapGradient / size + ridge * gapWeight);
    }

    var brier = 0.0;
    var marketBrier = 0.0;
    var logLoss = 0.0;
    var marketLogLoss = 0.0;
    for (final observation in holdout) {
      final target = observation.outcome ? 1.0 : 0.0;
      final predicted = _sigmoid(
        _logit(observation.marketProbability) +
            bias +
            gapWeight * observation.gap,
      );
      brier += (predicted - target) * (predicted - target);
      marketBrier +=
          (observation.marketProbability - target) *
          (observation.marketProbability - target);
      logLoss += _crossEntropy(predicted, target);
      marketLogLoss += _crossEntropy(observation.marketProbability, target);
    }
    final size = holdout.length;
    brier /= size;
    marketBrier /= size;
    logLoss /= size;
    marketLogLoss /= size;

    // Beating the price on one of the two scores is a coin flip; both is the
    // weakest claim worth acting on, and even then only on the holdout.
    final adopted = brier < marketBrier && logLoss < marketLogLoss;
    return MarketResidualState(
      bias: bias,
      gapWeight: gapWeight,
      samples: ordered.length,
      holdout: size,
      brier: brier,
      marketBrier: marketBrier,
      logLoss: logLoss,
      marketLogLoss: marketLogLoss,
      adopted: adopted,
      note: adopted
          ? '已由 ${development.length} 筆樣本學得偏離：常數 '
                '${bias.toStringAsFixed(3)}、分歧保留 '
                '${gapWeight.toStringAsFixed(3)}；折外 Brier '
                '${brier.toStringAsFixed(4)} 勝市場價 '
                '${marketBrier.toStringAsFixed(4)}。'
          : '折外未同時勝過市場價（Brier ${brier.toStringAsFixed(4)} 對 '
                '${marketBrier.toStringAsFixed(4)}），偏離模型不啟用。',
      updatedAt: ordered.last.settledAt,
    );
  }

  static double _crossEntropy(double probability, double target) {
    final bounded = probability.clamp(1e-6, 1 - 1e-6);
    return -(target * log(bounded) + (1 - target) * log(1 - bounded));
  }
}
