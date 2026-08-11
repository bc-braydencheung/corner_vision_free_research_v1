import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/simulated_trade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calculates quarter-line probabilities and EV', () {
    final distribution = List<double>.filled(31, 0);
    distribution[9] = 0.3;
    distribution[10] = 0.2;
    distribution[11] = 0.5;
    final prediction = _prediction(distribution);

    final outcome = prediction.probabilities(direction: 'over', line: 10.25);

    expect(outcome.win, closeTo(0.5, 0.0001));
    expect(outcome.push, closeTo(0.1, 0.0001));
    expect(outcome.loss, closeTo(0.4, 0.0001));
    expect(
      prediction.expectedValue(direction: 'over', line: 10.25, odds: 2),
      closeTo(0.1, 0.0001),
    );
  });

  test('settles a split Asian line correctly', () {
    final trade = SimulatedTrade(
      id: 'trade',
      matchId: 'match',
      leagueCode: 'E0',
      leagueName: '英超',
      homeTeam: 'Alpha',
      awayTeam: 'Beta',
      matchDate: DateTime.utc(2026),
      createdAt: DateTime.utc(2025),
      direction: 'over',
      line: 10.25,
      odds: 2,
      stake: 10,
      modelWinProbability: 0.5,
      modelPushProbability: 0.1,
      expectedValue: 0.1,
      confidence: 'medium',
      status: 'open',
      actualTotalCorners: null,
      profit: null,
    );

    expect(trade.settle(totalCorners: 10).profit, closeTo(-5, 0.0001));
    expect(trade.settle(totalCorners: 11).profit, closeTo(10, 0.0001));
  });

  test('settles a simulated racing win market', () {
    final trade = SimulatedTrade(
      id: 'race-trade',
      matchId: 'HK:2026-07-15:HV:1',
      leagueCode: 'HK',
      leagueName: '香港賽馬',
      homeTeam: 'Alpha',
      awayTeam: '跑馬地第1場',
      matchDate: DateTime.utc(2026, 7, 15),
      createdAt: DateTime.utc(2026, 7, 14),
      direction: 'win',
      line: 0,
      odds: 5,
      stake: 10,
      modelWinProbability: 0.25,
      modelPushProbability: 0,
      expectedValue: 0.25,
      confidence: 'medium',
      status: 'open',
      actualTotalCorners: null,
      profit: null,
      sport: 'racing',
      marketType: 'win',
      selectionId: 'K001',
    );

    expect(trade.settleRacing(position: 1).profit, closeTo(40, 0.0001));
    expect(trade.settleRacing(position: 3).profit, closeTo(-10, 0.0001));
    final placeTrade = SimulatedTrade.fromJson({
      ...trade.toJson(),
      'marketType': 'place',
      'placeSlots': 3,
    });
    expect(placeTrade.settleRacing(position: 3).profit, closeTo(40, 0.0001));
    expect(placeTrade.settleRacing(position: 4).profit, closeTo(-10, 0.0001));
  });
}

MatchPrediction _prediction(List<double> distribution) {
  return MatchPrediction(
    matchId: 'match',
    leagueCode: 'E0',
    leagueName: '英超',
    mode: 'forecast',
    date: DateTime.utc(2026),
    homeTeam: 'Alpha',
    awayTeam: 'Beta',
    expectedHomeCorners: 5,
    expectedAwayCorners: 5,
    expectedTotalCorners: 10,
    actualTotalCorners: null,
    interval80: const [6, 15],
    confidence: 'medium',
    confidenceScore: 0.7,
    markets: const [
      MarketPrediction(
        line: 9.5,
        overProbability: 0.7,
        underProbability: 0.3,
        fairOverOdds: 1.43,
        fairUnderOdds: 3.33,
      ),
    ],
    totalDistribution: distribution,
    factors: const [],
    recommendation: 'model-view',
    forecastStage: 'T-24h',
    dataQuality: 1,
    modelStability: 0.8,
  );
}
