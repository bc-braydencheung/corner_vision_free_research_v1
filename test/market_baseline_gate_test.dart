import 'dart:math';

import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/market_baseline_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('withholds picks until enough settled matches carry a market price', () {
    final verdict = evaluateMarketBaseline(_records(40, modelEdge: 0.4));

    expect(verdict.status, 'insufficient');
    expect(verdict.samples, 40);
    expect(verdict.suspendPicks, isTrue);
    expect(verdict.message, contains('40／50'));
  });

  test('an unsettled ledger is treated exactly like a losing one', () {
    expect(MarketBaselineVerdict.empty.beatsMarket, isFalse);
    expect(MarketBaselineVerdict.empty.suspendPicks, isTrue);
    expect(evaluateMarketBaseline(const []).suspendPicks, isTrue);
  });

  test('a model no better than the price keeps the gate shut', () {
    final verdict = evaluateMarketBaseline(
      _records(200, modelEdge: 0, jitter: 0.05),
    );

    expect(verdict.samples, 200);
    expect(verdict.status, 'behind');
    expect(verdict.suspendPicks, isTrue);
    expect(verdict.confidence, lessThan(marketBaselineMinimumT));
    expect(verdict.message, contains('未在統計上勝過盤口'));
  });

  test('a smaller Brier is not on its own enough to open the gate', () {
    // This model only jitters the price, so any Brier it wins by is sampling
    // noise; the gate has to read the spread and not the difference alone.
    final verdict = evaluateMarketBaseline(
      _records(60, modelEdge: 0, jitter: 0.05, seed: 7),
    );

    expect(verdict.modelBrier, lessThan(verdict.marketBrier));
    expect(verdict.beatsMarket, isFalse);
  });

  test('a model clearly better than the price opens the gate', () {
    final verdict = evaluateMarketBaseline(_records(200, modelEdge: 0.4));

    expect(verdict.status, 'ahead');
    expect(verdict.beatsMarket, isTrue);
    expect(verdict.suspendPicks, isFalse);
    expect(verdict.modelBrier, lessThan(verdict.marketBrier));
    expect(verdict.modelBrier, lessThan(verdict.constantBrier));
    expect(verdict.confidence, greaterThan(marketBaselineMinimumT));
  });

  test('records without a stored market price are not scored', () {
    final scored = _records(60, modelEdge: 0.4);
    final unpriced = _records(
      60,
      modelEdge: 0.4,
      seed: 7,
    ).map(_withoutMarketPrice).toList();

    final verdict = evaluateMarketBaseline([...scored, ...unpriced]);

    expect(verdict.samples, 60);
  });

  test('open forecasts are not scored', () {
    final settled = _records(60, modelEdge: 0.4);
    final open = _records(60, modelEdge: 0.4, seed: 3).map(_reopen).toList();

    expect(evaluateMarketBaseline([...settled, ...open]).samples, 60);
  });
}

/// Matches whose outcome follows a hidden truth the market only half sees.
///
/// [modelEdge] is how far the model probability is pulled from the market
/// towards the truth, so `0` is a model that adds nothing and `0.4` is one that
/// is genuinely sharper than the price.
List<ShadowForecast> _records(
  int count, {
  required double modelEdge,
  double jitter = 0,
  int seed = 42,
}) {
  final random = Random(seed);
  return [
    for (var index = 0; index < count; index++)
      () {
        final truth = 0.2 + random.nextDouble() * 0.6;
        final market = (truth + (random.nextDouble() - 0.5) * 0.3).clamp(
          0.05,
          0.95,
        );
        final model =
            (market +
                    (truth - market) * modelEdge +
                    (random.nextDouble() - 0.5) * jitter)
                .clamp(0.05, 0.95);
        final over = random.nextDouble() < truth;
        final matchDate = DateTime.utc(2025, 1, 1).add(Duration(days: index));
        return ShadowForecast(
          id: 'E0:$index',
          matchId: 'HK$index',
          leagueCode: 'E0',
          leagueName: '英超',
          homeTeam: 'Home $index',
          awayTeam: 'Away $index',
          matchDate: matchDate,
          capturedAt: matchDate.subtract(const Duration(hours: 3)),
          modelVersion: 'test',
          expectedTotalCorners: 9.8,
          referenceMae: 2.6,
          referenceBrier: 0.24,
          over9_5Probability: model,
          marketOverProbability: market,
          actualTotalCorners: over ? 12 : 7,
          settledAt: matchDate.add(const Duration(hours: 2)),
        );
      }(),
  ];
}

ShadowForecast _withoutMarketPrice(ShadowForecast record) =>
    _copy(record, marketOverProbability: null);

ShadowForecast _reopen(ShadowForecast record) => _copy(
  record,
  settled: false,
  marketOverProbability: record.marketOverProbability,
);

ShadowForecast _copy(
  ShadowForecast record, {
  double? marketOverProbability,
  bool settled = true,
}) => ShadowForecast(
  id: '${record.id}:copy',
  matchId: record.matchId,
  leagueCode: record.leagueCode,
  leagueName: record.leagueName,
  homeTeam: record.homeTeam,
  awayTeam: record.awayTeam,
  matchDate: record.matchDate,
  capturedAt: record.capturedAt,
  modelVersion: record.modelVersion,
  expectedTotalCorners: record.expectedTotalCorners,
  referenceMae: record.referenceMae,
  referenceBrier: record.referenceBrier,
  over9_5Probability: record.over9_5Probability,
  marketOverProbability: marketOverProbability,
  actualTotalCorners: settled ? record.actualTotalCorners : null,
  settledAt: settled ? record.settledAt : null,
);
