import 'dart:convert';
import 'dart:ui' as ui;

import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/simulated_trade.dart';
import 'package:edgewise/models/simulation_draft.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/hkjc_shadow.dart';
import 'package:edgewise/services/simulation_backup_service.dart';
import 'package:edgewise/services/simulation_entry.dart';
import 'package:edgewise/services/simulation_ledger.dart';
import 'package:edgewise/services/simulation_service.dart';
import 'package:edgewise/services/simulation_share.dart';
import 'package:edgewise/services/simulation_share_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 8, 20, 12);

SimulationDraft _draft({
  String matchId = 'hkjc-1',
  String sport = 'football',
  String marketType = 'corners',
  String direction = 'over',
  double line = 9.5,
  double odds = 2.0,
  double modelProbability = 0.58,
  double marketProbability = 0.5,
  bool recommended = true,
  String? selectionId,
  DateTime? startTime,
}) {
  return SimulationDraft(
    sport: sport,
    marketType: marketType,
    matchId: matchId,
    leagueCode: 'I1',
    leagueName: '意甲',
    homeTeam: '博洛尼亞',
    awayTeam: '拉素',
    startTime: startTime ?? _now.add(const Duration(hours: 5)),
    selectionLabel: '角球 9.5 大',
    direction: direction,
    line: line,
    odds: odds,
    modelProbability: modelProbability,
    marketProbability: marketProbability,
    edge: modelProbability * odds - 1,
    confidence: 0.52,
    confidenceLabel: '中',
    recommended: recommended,
    selectionId: selectionId,
    stakeFraction: 0.012,
    marketSource: '馬會足球角球盤',
    marketCapturedAt: _now,
  );
}

SimulatedTrade _trade({
  required String id,
  String status = 'open',
  double stake = 100,
  double odds = 2,
  double? profit,
  DateTime? matchDate,
  String sport = 'football',
  int? actualTotalCorners,
}) {
  return SimulatedTrade(
    id: id,
    matchId: id,
    leagueCode: 'I1',
    leagueName: '意甲',
    homeTeam: '博洛尼亞',
    awayTeam: '拉素',
    matchDate: matchDate ?? _now,
    createdAt: (matchDate ?? _now).subtract(const Duration(hours: 3)),
    direction: 'over',
    line: 9.5,
    odds: odds,
    stake: stake,
    modelWinProbability: 0.58,
    modelPushProbability: 0,
    expectedValue: 0.16,
    confidence: '中',
    status: status,
    actualTotalCorners: actualTotalCorners,
    profit: profit,
    sport: sport,
    selectionLabel: '角球 9.5 大',
    marketProbability: 0.5,
  );
}

void main() {
  group('simulation draft', () {
    test('records the published line, price and probabilities', () {
      final trade = _draft().toTrade(stake: 150, now: _now);

      expect(trade.matchId, 'hkjc-1');
      expect(trade.line, 9.5);
      expect(trade.odds, 2.0);
      expect(trade.stake, 150);
      expect(trade.modelWinProbability, 0.58);
      expect(trade.marketProbability, 0.5);
      expect(trade.status, 'open');
      expect(trade.profit, isNull);
      expect(trade.recommended, isTrue);
      expect(trade.selectionLabel, '角球 9.5 大');
      expect(trade.marketSource, '馬會足球角球盤');
      expect(trade.marketCapturedAt, _now);
      expect(trade.stakeStrategy, 'manual');
    });

    test('keeps the HKJC match id of the fixture the card showed', () {
      final draft = cornerSimulationDraft(
        leagueCode: 'I1',
        leagueName: '意甲',
        fixture: _fixture(
          matchId: 'hkjc-uuid-1',
          kickOff: _now.add(const Duration(hours: 4)),
        ),
        pick: const HkjcCornerRecommendation(
          line: HkjcCornerLineAssessment(
            line: HkjcMarketLine(
              lineId: '1',
              condition: '9.5',
              line: 9.5,
              main: true,
              status: 'AVAILABLE',
              highOdds: 2.0,
              lowOdds: 1.8,
            ),
            marketHighProbability: 0.47,
            marketLowProbability: 0.53,
            overround: 0.05,
            modelHighProbability: 0.58,
            modelPushProbability: 0,
            modelHighEdge: 0.16,
            modelLowEdge: -0.24,
            uncalibratedHighProbability: 0.57,
            calibratedHighProbability: 0.58,
          ),
          direction: 'high',
          odds: 2.0,
          edge: 0.16,
          winProbability: 0.58,
          confidence: 0.5,
        ),
        recommended: true,
        capturedAt: _now,
      );

      expect(draft.matchId, 'hkjc-uuid-1');
      expect(draft.direction, 'over');
      expect(draft.line, 9.5);
      expect(draft.odds, 2.0);
      expect(draft.modelProbability, 0.58);
      expect(draft.marketProbability, 0.47);
      expect(draft.homeTeam, '博洛尼亞');
      expect(draft.recommended, isTrue);
    });
  });

  group('simulation ledger', () {
    test('leaves open stakes out of profit but inside exposure', () {
      final ledger = buildSimulationLedger(
        trades: [
          _trade(id: 'open-1', stake: 200),
          _trade(id: 'won-1', status: 'settled', stake: 100, profit: 100),
        ],
        bankroll: 10000,
      );

      expect(ledger.profit, 100);
      expect(ledger.balance, 10100);
      expect(ledger.openStake, 200);
      expect(ledger.available, 9900);
      expect(ledger.openCount, 1);
      expect(ledger.settledCount, 1);
      expect(ledger.wins, 1);
      expect(ledger.losses, 0);
      expect(ledger.roi, 1);
      expect(ledger.hitRate, 1);
    });

    test('measures drawdown on the settled sequence and counts pushes', () {
      final ledger = buildSimulationLedger(
        trades: [
          _trade(
            id: 'a',
            status: 'settled',
            stake: 1000,
            profit: 1000,
            matchDate: DateTime.utc(2026, 8, 1),
          ),
          _trade(
            id: 'b',
            status: 'settled',
            stake: 3000,
            profit: -3000,
            matchDate: DateTime.utc(2026, 8, 2),
          ),
          _trade(
            id: 'c',
            status: 'settled',
            stake: 500,
            profit: 0,
            matchDate: DateTime.utc(2026, 8, 3),
          ),
        ],
        bankroll: 10000,
      );

      expect(ledger.profit, -2000);
      expect(ledger.wins, 1);
      expect(ledger.losses, 1);
      expect(ledger.pushes, 1);
      // Equity peaked at 11000 and fell to 8000.
      expect(ledger.maximumDrawdown, closeTo(3000 / 11000, 1e-9));
    });

    test('reads an empty account as flat rather than as a loss', () {
      final ledger = buildSimulationLedger(trades: const [], bankroll: 500);

      expect(ledger.balance, 500);
      expect(ledger.available, 500);
      expect(ledger.hasSettled, isFalse);
      expect(ledger.roi, 0);
      expect(ledger.hitRate, 0);
      expect(ledger.maximumDrawdown, 0);
    });

    test('lists unsettled rows first, then newest events', () {
      final ordered = sortSimulationTrades([
        _trade(
          id: 'old-settled',
          status: 'settled',
          profit: 10,
          matchDate: DateTime.utc(2026, 8, 1),
        ),
        _trade(
          id: 'new-settled',
          status: 'settled',
          profit: 10,
          matchDate: DateTime.utc(2026, 8, 9),
        ),
        _trade(id: 'open', matchDate: DateTime.utc(2026, 7, 1)),
      ]);

      expect(ordered.map((trade) => trade.id), [
        'open',
        'new-settled',
        'old-settled',
      ]);
    });
  });

  group('settlement', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('settles a football row from the HKJC corner totals', () async {
      final trades = await SimulationService().settle(
        [_trade(id: 'hkjc-1', stake: 100, odds: 2)],
        const [],
        hkjcCornerTotals: const {'hkjc-1': 12},
      );

      expect(trades.single.status, 'settled');
      expect(trades.single.actualTotalCorners, 12);
      expect(trades.single.profit, 100);
      expect(trades.single.won, isTrue);
    });

    test('prefers the HKJC count over a bridged free-dataset result', () async {
      final trades = await SimulationService().settle(
        [_trade(id: 'hkjc-1', stake: 100, odds: 2)],
        const [MatchResult(matchId: 'hkjc-1', actualTotalCorners: 4)],
        hkjcCornerTotals: const {'hkjc-1': 12},
      );

      expect(trades.single.actualTotalCorners, 12);
      expect(trades.single.profit, 100);
    });

    test('splits a quarter line into its two components', () async {
      final draft = _draft(line: 9.75, odds: 2);
      final trades = await SimulationService().settle(
        [draft.toTrade(stake: 100, now: _now)],
        const [],
        hkjcCornerTotals: const {'hkjc-1': 10},
      );

      // 10 beats 9.5 and loses to 10.0, so half wins and half is void.
      expect(trades.single.profit, closeTo(50, 1e-9));
    });

    test('never settles a racing row from a corner count', () async {
      final racing = _draft(
        sport: 'racing',
        marketType: 'win',
        matchId: 'race-1',
        direction: 'win',
        line: 0,
        selectionId: 'horse-9',
      ).toTrade(stake: 100, now: _now);

      final unrelated = await SimulationService().settle(
        [racing],
        const [],
        hkjcCornerTotals: const {'race-1': 12},
      );
      expect(unrelated.single.status, 'open');

      final settled = await SimulationService().settle(
        [racing],
        const [],
        racingResults: const [
          RacingResult(raceId: 'race-1', horseId: 'horse-9', finishPosition: 1),
        ],
      );
      expect(settled.single.status, 'settled');
      expect(settled.single.finishPosition, 1);
      expect(settled.single.profit, 100);
    });

    test('clearing removes only the simulated rows', () async {
      SharedPreferences.setMockInitialValues({
        'edgewise_shadow_forecasts_v1': '[]',
      });
      final service = SimulationService();
      await service.save([_trade(id: 'a')]);
      await service.saveBankroll(2500);

      await service.clear();

      expect(await service.load(), isEmpty);
      expect(await service.loadBankroll(), 2500);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('edgewise_shadow_forecasts_v1'), '[]');
    });

    test('bankroll falls back to the default before one is chosen', () async {
      expect(
        await SimulationService().loadBankroll(),
        SimulationService.defaultBankroll,
      );
    });

    test('HKJC corner totals only carry settled, plausible fixtures', () {
      final totals = hkjcCornerTotals(
        snapshot: HkjcFootballSnapshot(
          capturedAt: _now,
          fixtures: [
            _fixture(
              matchId: 'done',
              kickOff: _now.subtract(const Duration(hours: 4)),
              homeCorner: 6,
              awayCorner: 7,
            ),
            _fixture(
              matchId: 'just-off',
              kickOff: _now.subtract(const Duration(minutes: 10)),
              homeCorner: 1,
              awayCorner: 1,
            ),
            _fixture(
              matchId: 'impossible',
              kickOff: _now.subtract(const Duration(hours: 4)),
              homeCorner: 30,
              awayCorner: 30,
            ),
          ],
        ),
        asOf: _now,
      );

      expect(totals, {'done': 13});
    });
  });

  group('json backup', () {
    const service = SimulationBackupService();

    test('round-trips trades and the bankroll', () {
      final trades = [
        _trade(id: 'open-1'),
        _trade(id: 'settled-1', status: 'settled', profit: 90),
      ];

      final imported = service.decode(
        service.encode(trades: trades, bankroll: 12345, asOf: _now),
      );

      expect(imported.bankroll, 12345);
      expect(imported.trades, hasLength(2));
      expect(imported.trades.first.id, 'open-1');
      expect(imported.trades.last.profit, 90);
      expect(imported.trades.first.selectionLabel, '角球 9.5 大');
    });

    test('rejects malformed and foreign files', () {
      expect(
        () => service.decode('not json'),
        throwsA(isA<SimulationImportException>()),
      );
      expect(
        () => service.decode('[]'),
        throwsA(isA<SimulationImportException>()),
      );
      expect(
        () => service.decode(jsonEncode({'schema': 'something-else'})),
        throwsA(isA<SimulationImportException>()),
      );
      expect(
        () => service.decode(
          jsonEncode({
            'schema': simulationBackupSchema,
            'schemaVersion': simulationBackupSchemaVersion + 1,
            'trades': const [],
          }),
        ),
        throwsA(isA<SimulationImportException>()),
      );
      expect(
        () => service.decode(
          jsonEncode({
            'schema': simulationBackupSchema,
            'schemaVersion': simulationBackupSchemaVersion,
          }),
        ),
        throwsA(isA<SimulationImportException>()),
      );
    });

    test('rejects invalid rows instead of repairing them', () {
      String document(Map<String, Object?> overrides) {
        final row = _trade(id: 'a').toJson()..addAll(overrides);
        return jsonEncode({
          'schema': simulationBackupSchema,
          'schemaVersion': simulationBackupSchemaVersion,
          'trades': [row],
        });
      }

      for (final broken in <Map<String, Object?>>[
        {'odds': 0.5},
        {'stake': 0},
        {'line': -1},
        {'status': 'cashed-out'},
        {'matchDate': 'yesterday'},
        {'id': null},
        {'modelWinProbability': null},
      ]) {
        expect(
          () => service.decode(document(broken)),
          throwsA(isA<SimulationImportException>()),
          reason: 'accepted $broken',
        );
      }

      expect(
        () => service.decode(
          jsonEncode({
            'schema': simulationBackupSchema,
            'schemaVersion': simulationBackupSchemaVersion,
            'trades': const ['not-a-row'],
          }),
        ),
        throwsA(isA<SimulationImportException>()),
      );
    });

    test('rejects duplicate ids and inconsistent settled rows', () {
      String document(List<SimulatedTrade> trades) => jsonEncode({
        'schema': simulationBackupSchema,
        'schemaVersion': simulationBackupSchemaVersion,
        'trades': trades.map((trade) => trade.toJson()).toList(),
      });

      expect(
        () =>
            service.decode(document([_trade(id: 'same'), _trade(id: 'same')])),
        throwsA(isA<SimulationImportException>()),
      );
      expect(
        () => service.decode(document([_trade(id: 'a', status: 'settled')])),
        throwsA(isA<SimulationImportException>()),
      );
    });

    test('drops an invalid bankroll rather than importing it', () {
      final imported = service.decode(
        jsonEncode({
          'schema': simulationBackupSchema,
          'schemaVersion': simulationBackupSchemaVersion,
          'bankroll': -5,
          'trades': const [],
        }),
      );

      expect(imported.bankroll, isNull);
      expect(imported.trades, isEmpty);
    });
  });

  group('share text', () {
    test('states the price, stake and the simulation disclosure', () {
      final text = buildSimulationTradeShareText(
        trade: _trade(id: 'a', stake: 100, odds: 2),
        asOf: _now,
      );

      expect(text, contains('模擬戶口'));
      expect(text, contains('角球 9.5 大 @ 2.00'));
      expect(text, contains('注碼 100.00'));
      expect(text, contains('中則可得 200.00'));
      expect(text, contains('模型機率 58.0%'));
      expect(text, contains('待賽果自動結算'));
      expect(text, contains('不涉及真實資金或投注'));
    });

    test('reports the settled result and profit', () {
      final text = buildSimulationTradeShareText(
        trade: _trade(
          id: 'a',
          status: 'settled',
          stake: 100,
          profit: -100,
          actualTotalCorners: 7,
        ),
        asOf: _now,
      );

      expect(text, contains('7 個角球'));
      expect(text, contains('盈虧 -100.00'));
    });

    test('says when the ledger listing is truncated', () {
      final trades = [
        for (var index = 0; index < simulationShareEntries + 4; index++)
          _trade(
            id: 'row-$index',
            status: 'settled',
            profit: 10,
            matchDate: _now.subtract(Duration(days: index + 1)),
          ),
      ];

      final text = buildSimulationLedgerShareText(
        trades: trades,
        ledger: buildSimulationLedger(trades: trades, bankroll: 10000),
        asOf: _now,
      );

      expect(text, contains('共 ${trades.length} 注'));
      expect(text, contains('只列最近 $simulationShareEntries 注'));
      expect(text, contains('不涉及真實資金或投注'));
    });

    test('does not claim a hit rate before anything settles', () {
      final trades = [_trade(id: 'open-1')];

      final text = buildSimulationLedgerShareText(
        trades: trades,
        ledger: buildSimulationLedger(trades: trades, bankroll: 10000),
        asOf: _now,
      );

      expect(text, contains('命中率：未有已結算賽果'));
      expect(text, contains('ROI：未有已結算賽果'));
    });
  });

  group('share images', () {
    testWidgets('render at share resolution', (tester) async {
      // PNG encoding is real asynchronous work, so it cannot run on the fake
      // clock the widget tester installs.
      await tester.runAsync(() async {
        final trades = [
          for (var index = 0; index < simulationShareEntries + 5; index++)
            _trade(
              id: 'row-$index',
              status: index.isEven ? 'settled' : 'open',
              profit: index.isEven ? 90 : null,
              actualTotalCorners: index.isEven ? 12 : null,
              matchDate: _now.subtract(Duration(days: index + 1)),
            ),
        ];
        final single = await renderSimulationTradeShareImage(
          trade: trades.first,
          asOf: _now,
        );
        final empty = await renderSimulationLedgerShareImage(
          trades: const [],
          ledger: buildSimulationLedger(trades: const [], bankroll: 10000),
          asOf: _now,
        );
        final full = await renderSimulationLedgerShareImage(
          trades: trades,
          ledger: buildSimulationLedger(trades: trades, bankroll: 10000),
          asOf: _now,
        );

        for (final image in [single, empty, full]) {
          expect(image.width, 3240);
          expect(image.height, greaterThan(1200));
          final decoded = await ui.instantiateImageCodec(image.bytes);
          final frame = await decoded.getNextFrame();
          expect(frame.image.width, image.width);
          expect(frame.image.height, image.height);
        }
        expect(full.height, greaterThan(empty.height));
      });
    });

    test('single-bet rows are drawn clear of the selection badge', () {
      final layout = simulationTradeCardLayout(_trade(id: 'a'));

      expect(layout.rowsTop, greaterThanOrEqualTo(layout.badgeBottom));
      expect(layout.rows, greaterThan(1));
      // The disclosure footer still fits under the last row.
      expect(layout.height, greaterThan(layout.rowsBottom + 100));
    });
  });
}

HkjcFootballFixture _fixture({
  required String matchId,
  required DateTime kickOff,
  int? homeCorner,
  int? awayCorner,
}) => HkjcFootballFixture(
  matchId: matchId,
  frontEndId: matchId,
  leagueCode: 'I1',
  tournamentCode: 'I1',
  tournamentName: '意甲',
  kickOffTime: kickOff,
  status: 'RESULT',
  homeTeam: '博洛尼亞',
  awayTeam: '拉素',
  homeTeamEnglish: 'Bologna',
  awayTeamEnglish: 'Lazio',
  cornerLines: const [],
  homeCorner: homeCorner,
  awayCorner: awayCorner,
);
