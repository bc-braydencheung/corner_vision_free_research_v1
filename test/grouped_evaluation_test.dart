import 'dart:math';

import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/grouped_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an empty ledger claims nothing', () {
    final evaluation = evaluateGroups(const []);

    expect(evaluation.samples, 0);
    expect(evaluation.positiveGroups, isEmpty);
    expect(evaluation.message, contains('無法分組比較'));
  });

  test('splits the ledger by league, shown line and lead time', () {
    final evaluation = evaluateGroups([
      ..._records(30, league: '英超', line: 9.5, lead: const Duration(hours: 1)),
      ..._records(
        30,
        league: '西甲',
        line: 10.5,
        lead: const Duration(hours: 30),
        seed: 2,
      ),
    ]);

    expect(evaluation.samples, 60);
    expect(evaluation.byLeague.map((group) => group.label), ['英超', '西甲']);
    expect(evaluation.byLine.map((group) => group.label), ['9.5 盤', '10.5 盤']);
    expect(evaluation.byLeadTime.map((group) => group.label), [
      '開賽前 2 小時內',
      '開賽前逾 24 小時',
    ]);
    expect(evaluation.byLeague.every((group) => group.samples == 30), isTrue);
  });

  test('a subset under 20 matches reports no interval', () {
    final evaluation = evaluateGroups(
      _records(12, league: '法甲', line: 9.5, lead: const Duration(hours: 3)),
    );
    final group = evaluation.byLeague.single;

    expect(group.sufficient, isFalse);
    expect(group.positive, isFalse);
    expect(group.gainLow, 0);
    expect(group.gainHigh, 0);
    expect(group.verdict, contains('樣本不足'));
  });

  test('a subset that only jitters the price is not called an edge', () {
    final evaluation = evaluateGroups(
      _records(
        60,
        league: '意甲',
        line: 9.5,
        lead: const Duration(hours: 3),
        modelEdge: 0,
        jitter: 0.05,
      ),
    );
    final group = evaluation.byLeague.single;

    expect(group.sufficient, isTrue);
    expect(group.positive, isFalse);
    expect(group.gainLow, lessThan(0));
    expect(group.verdict, '未分勝負');
    expect(evaluation.message, contains('沒有任何'));
  });

  test('a genuinely sharper subset has its whole interval above zero', () {
    final evaluation = evaluateGroups(
      _records(
        120,
        league: '德甲',
        line: 9.5,
        lead: const Duration(hours: 3),
        modelEdge: 0.6,
      ),
    );
    final group = evaluation.byLeague.single;

    expect(group.positive, isTrue);
    expect(group.gainLow, greaterThan(0));
    expect(group.gain, greaterThan(group.gainLow));
    expect(group.gain, lessThan(group.gainHigh));
    expect(group.modelBrier, lessThan(group.marketBrier));
    expect(group.verdict, '勝過盤口');
    expect(
      evaluation.positiveGroups.map((score) => score.label),
      contains('德甲'),
    );
  });

  test('records lacking a market price or a result are not grouped', () {
    final scored = _records(
      30,
      league: '英超',
      line: 9.5,
      lead: const Duration(hours: 3),
    );
    final unusable = [
      _strip(scored.first, marketPrice: false),
      _strip(scored.last, settled: false),
    ];

    expect(evaluateGroups([...scored, ...unusable]).samples, 30);
  });

  test('the interval is reproducible for the same ledger', () {
    final records = _records(
      40,
      league: '英超',
      line: 9.5,
      lead: const Duration(hours: 3),
      modelEdge: 0.5,
    );

    expect(
      evaluateGroups(records).byLeague.single.gainLow,
      evaluateGroups(records).byLeague.single.gainLow,
    );
  });
}

List<ShadowForecast> _records(
  int count, {
  required String league,
  required double line,
  required Duration lead,
  double modelEdge = 0.5,
  double jitter = 0,
  int seed = 11,
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
        final matchDate = DateTime.utc(2025, 2, 1).add(Duration(days: index));
        return ShadowForecast(
          id: '$league:$index',
          matchId: 'HK-$league-$index',
          leagueCode: 'X',
          leagueName: league,
          homeTeam: 'Home $index',
          awayTeam: 'Away $index',
          matchDate: matchDate,
          capturedAt: matchDate.subtract(lead),
          modelVersion: 'test',
          expectedTotalCorners: 9.7,
          referenceMae: 2.6,
          referenceBrier: 0.24,
          over9_5Probability: model,
          marketOverProbability: market,
          pick: ShadowPick(
            line: line,
            direction: 'high',
            odds: 1.9,
            modelProbability: model,
            marketProbability: market,
            edge: 0.01,
            recommended: false,
          ),
          actualTotalCorners: over ? 12 : 7,
          settledAt: matchDate.add(const Duration(hours: 2)),
        );
      }(),
  ];
}

ShadowForecast _strip(
  ShadowForecast record, {
  bool marketPrice = true,
  bool settled = true,
}) => ShadowForecast(
  id: '${record.id}:stripped',
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
  marketOverProbability: marketPrice ? record.marketOverProbability : null,
  pick: record.pick,
  actualTotalCorners: settled ? record.actualTotalCorners : null,
  settledAt: settled ? record.settledAt : null,
);
