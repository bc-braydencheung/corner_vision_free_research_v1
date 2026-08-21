import 'dart:math';

import 'package:edgewise/services/market_residual.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const learner = MarketResidualLearner();

  test('too few settled quotes refuses to fit at all', () {
    final state = learner.fit(_biased(count: minimumResidualSamples - 1));

    expect(state.adopted, isFalse);
    expect(state.gapWeight, 0);
    expect(state.holdout, 0);
    expect(state.note, contains('$minimumResidualSamples'));
    // An unfitted correction has to leave the quote exactly where it was.
    expect(state.predict(market: 0.42, model: 0.75), closeTo(0.42, 1e-12));
  });

  test('an unadopted fit never moves a displayed probability', () {
    final state = learner.fit(_noise(count: 200));

    expect(state.samples, 200);
    if (!state.adopted) {
      expect(state.predict(market: 0.42, model: 0.75), closeTo(0.42, 1e-12));
    }
  });

  test('a market with a known bias is corrected towards the outcome', () {
    // Every quote is 8 points too low and the model sees the same direction,
    // so the residual fit has something real to learn.
    final state = learner.fit(_biased(count: 400));

    expect(state.adopted, isTrue);
    expect(state.samples, 400);
    expect(state.holdout, greaterThan(0));
    expect(state.brier, lessThan(state.marketBrier));
    expect(state.logLoss, lessThan(state.marketLogLoss));
    expect(state.beatsMarket, isTrue);
    // The correction has to push above the quote, not below it.
    expect(state.predict(market: 0.50, model: 0.58), greaterThan(0.50));
  });

  test('the correction reads the quote as its offset', () {
    final state = learner.fit(_biased(count: 400));

    // Same disagreement on two different quotes has to stay ordered by quote.
    final low = state.predict(market: 0.30, model: 0.38);
    final high = state.predict(market: 0.70, model: 0.78);
    expect(low, lessThan(high));
  });

  test('an extreme disagreement is capped instead of dominating', () {
    final state = learner.fit(_biased(count: 400));

    final capped = state.predict(market: 0.5, model: 1 - 1e-9);
    final atCap = state.predict(
      market: 0.5,
      model: 1 / (1 + exp(-residualGapCap)),
    );
    expect(capped, closeTo(atCap, 1e-9));
  });

  test('state round trips through json', () {
    final state = learner.fit(_biased(count: 400));
    final restored = MarketResidualState.fromJson(state.toJson());

    expect(restored.adopted, state.adopted);
    expect(restored.bias, closeTo(state.bias, 1e-12));
    expect(restored.gapWeight, closeTo(state.gapWeight, 1e-12));
    expect(restored.samples, state.samples);
    expect(restored.holdout, state.holdout);
    expect(restored.brier, closeTo(state.brier, 1e-12));
    expect(restored.marketLogLoss, closeTo(state.marketLogLoss, 1e-12));
    expect(
      restored.predict(market: 0.5, model: 0.6),
      closeTo(state.predict(market: 0.5, model: 0.6), 1e-12),
    );
  });
}

/// Quotes that are systematically eight points below the true rate.
List<MarketResidualObservation> _biased({required int count}) {
  final random = Random(7);
  final observations = <MarketResidualObservation>[];
  for (var index = 0; index < count; index++) {
    final market = 0.35 + 0.3 * random.nextDouble();
    final truth = (market + 0.08).clamp(0.01, 0.99);
    observations.add(
      MarketResidualObservation(
        settledAt: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        outcome: random.nextDouble() < truth,
        // The model leans the same way the truth does, which is what the
        // correction is allowed to act on.
        modelProbability: (market + 0.06).clamp(0.01, 0.99),
        marketProbability: market,
      ),
    );
  }
  return observations;
}

/// A perfectly fair market with a model that only adds noise.
List<MarketResidualObservation> _noise({required int count}) {
  final random = Random(11);
  final observations = <MarketResidualObservation>[];
  for (var index = 0; index < count; index++) {
    final market = 0.35 + 0.3 * random.nextDouble();
    observations.add(
      MarketResidualObservation(
        settledAt: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        outcome: random.nextDouble() < market,
        modelProbability: (market + (random.nextDouble() - 0.5) * 0.2).clamp(
          0.01,
          0.99,
        ),
        marketProbability: market,
      ),
    );
  }
  return observations;
}
