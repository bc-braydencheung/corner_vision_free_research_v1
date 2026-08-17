import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/market_anchor.dart';
import 'package:edgewise/services/market_anchor_service.dart';
import 'package:flutter_test/flutter_test.dart';

MarketAnchorObservation _observation({
  required int index,
  required bool outcome,
  required double model,
  required double market,
}) {
  return MarketAnchorObservation(
    settledAt: DateTime.utc(2026, 1, 1).add(Duration(days: index)),
    outcome: outcome,
    modelProbability: model,
    marketProbability: market,
  );
}

ShadowForecast _record({
  required String id,
  double? marketOverProbability,
  int? actual,
}) {
  final match = DateTime.utc(2026, 3, 1);
  return ShadowForecast(
    id: id,
    matchId: id,
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: 'A',
    awayTeam: 'B',
    matchDate: match,
    capturedAt: match.subtract(const Duration(hours: 3)),
    modelVersion: 'v1',
    expectedTotalCorners: 10.2,
    over9_5Probability: 0.6,
    referenceMae: 2.8,
    referenceBrier: 0.25,
    marketOverProbability: marketOverProbability,
    actualTotalCorners: actual,
    settledAt: actual == null ? null : match.add(const Duration(hours: 2)),
  );
}

void main() {
  test('keeps the documented conservative anchor before it is measured', () {
    final state = const MarketAnchorLearner().replay([
      for (var index = 0; index < 12; index++)
        _observation(
          index: index,
          outcome: index.isEven,
          model: 0.7,
          market: 0.5,
        ),
    ]);

    expect(state.samples, 12);
    expect(state.learned, isFalse);
    expect(state.share, defaultMarketAnchor);
    expect(state.note, contains('保守預設'));
  });

  test('learns a high anchor when the model beats the price', () {
    // The model is right about the direction the price is wrong in.
    final observations = <MarketAnchorObservation>[];
    for (var index = 0; index < 120; index++) {
      final outcome = index % 4 != 0;
      observations.add(
        _observation(index: index, outcome: outcome, model: 0.75, market: 0.5),
      );
    }
    final state = const MarketAnchorLearner().replay(observations);

    expect(state.learned, isTrue);
    expect(state.share, greaterThan(defaultMarketAnchor));
    expect(state.brier, lessThan(state.marketBrier));
    expect(state.beatsMarket, isTrue);
  });

  test('learns a low anchor when the model is worse than the price', () {
    final observations = <MarketAnchorObservation>[];
    for (var index = 0; index < 120; index++) {
      // The price is calibrated at 0.5; the model insists on 0.95.
      observations.add(
        _observation(
          index: index,
          outcome: index.isEven,
          model: 0.95,
          market: 0.5,
        ),
      );
    }
    final state = const MarketAnchorLearner().replay(observations);

    expect(state.learned, isTrue);
    expect(state.share, lessThan(defaultMarketAnchor));
    expect(state.beatsMarket, isFalse);
  });

  test('forgets what it learned when the loss stream drifts', () {
    final observations = <MarketAnchorObservation>[];
    for (var index = 0; index < 60; index++) {
      observations.add(
        _observation(index: index, outcome: true, model: 0.9, market: 0.5),
      );
    }
    for (var index = 60; index < 160; index++) {
      observations.add(
        _observation(index: index, outcome: false, model: 0.9, market: 0.5),
      );
    }
    final state = const MarketAnchorLearner().replay(observations);

    expect(state.samples, 160);
    // Either the detector is still holding an alarm (conservative share) or it
    // reset the weights after one, but the anchor must not stay extreme.
    expect(state.share, lessThanOrEqualTo(defaultMarketAnchor + 1e-9));
  });

  test('round-trips through json', () {
    final state = const MarketAnchorLearner().replay([
      for (var index = 0; index < 40; index++)
        _observation(
          index: index,
          outcome: index % 3 != 0,
          model: 0.68,
          market: 0.55,
        ),
    ]);
    final restored = MarketAnchorState.fromJson(state.toJson());

    expect(restored.samples, state.samples);
    expect(restored.share, closeTo(state.share, 1e-9));
    expect(restored.marketBrier, closeTo(state.marketBrier, 1e-9));
  });

  test('only settled records carrying a market price are learned from', () {
    final service = MarketAnchorService();
    final observations = service.observations([
      _record(id: 'open', marketOverProbability: 0.52),
      _record(id: 'no-price', actual: 11),
      _record(id: 'usable', marketOverProbability: 0.52, actual: 11),
    ]);

    expect(observations, hasLength(1));
    expect(observations.single.outcome, isTrue);
    expect(observations.single.marketProbability, 0.52);
  });

  test('the corner model applies the anchor once, on the probability', () {
    final anchored = HkjcCornerModel(
      anchor: const MarketAnchorLearner().replay([
        for (var index = 0; index < 120; index++)
          _observation(
            index: index,
            outcome: index % 4 != 0,
            model: 0.75,
            market: 0.5,
          ),
      ]),
    );
    final unmeasured = const HkjcCornerModel();

    expect(unmeasured.modelTrust, defaultMarketAnchor);
    expect(anchored.modelTrust, greaterThan(unmeasured.modelTrust));
    expect(anchored.modelTrust, lessThanOrEqualTo(1));
  });
}
