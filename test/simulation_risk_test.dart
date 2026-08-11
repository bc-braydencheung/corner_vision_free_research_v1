import 'package:edgewise/models/simulated_trade.dart';
import 'package:edgewise/services/simulation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('limits each new simulation to 0.5 percent', () {
    final risk = SimulationService().riskSummary(const []);

    expect(risk.maximumNewStake, 5);
    expect(risk.stopped, isFalse);
  });

  test('stops new simulations after 15 percent drawdown', () {
    final trades = [
      _settled('win', DateTime.utc(2026, 1, 1), 100),
      _settled('loss', DateTime.utc(2026, 1, 2), -180),
    ];

    final risk = SimulationService().riskSummary(trades);

    expect(risk.maximumDrawdown, greaterThan(0.15));
    expect(risk.stopped, isTrue);
    expect(risk.reason, contains('15%'));
  });

  test('counts settled and open stake in the event-day exposure limit', () {
    final date = DateTime.utc(2026, 1, 2);
    final trades = [
      for (var index = 0; index < 4; index++)
        _settled('day-$index', date, 0, stake: 5),
    ];

    final risk = SimulationService().riskSummary(trades, eventDate: date);

    expect(risk.dayExposure, 20);
    expect(risk.maximumNewStake, 0);
    expect(risk.stopped, isTrue);
  });
}

SimulatedTrade _settled(
  String id,
  DateTime date,
  double profit, {
  double stake = 5,
}) {
  return SimulatedTrade(
    id: id,
    matchId: id,
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: 'Alpha',
    awayTeam: 'Beta',
    matchDate: date,
    createdAt: date,
    direction: 'over',
    line: 9.5,
    odds: 2,
    stake: stake,
    modelWinProbability: 0.55,
    modelPushProbability: 0,
    expectedValue: 0.1,
    confidence: 'high',
    status: 'settled',
    actualTotalCorners: 11,
    profit: profit,
  );
}
