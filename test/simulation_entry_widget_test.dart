import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/simulated_trade.dart';
import 'package:edgewise/models/simulation_draft.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/widgets/hkjc_corner_section.dart';
import 'package:edgewise/widgets/simulation_account.dart';
import 'package:edgewise/widgets/simulation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kick-off gating is evaluated against the wall clock, so the fixtures sit a
/// few hours ahead of it rather than on a fixed date.
final _now = DateTime.now().toUtc();

/// Equal prices: the model has no edge, so the card only watches the fixture.
const _agreeing = [
  HkjcMarketLine(
    lineId: '1',
    condition: '9.5',
    line: 9.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 1.9,
    lowOdds: 1.9,
  ),
];

/// A line priced far from the rest of the board, which clears the gate.
const _mispriced = [
  HkjcMarketLine(
    lineId: '1',
    condition: '8.5',
    line: 8.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 1.5,
    lowOdds: 2.5,
  ),
  HkjcMarketLine(
    lineId: '2',
    condition: '9.5',
    line: 9.5,
    main: false,
    status: 'AVAILABLE',
    highOdds: 3.2,
    lowOdds: 1.35,
  ),
];

HkjcFootballFixture _fixture(List<HkjcMarketLine> lines) => HkjcFootballFixture(
  matchId: 'hkjc-1',
  frontEndId: 'hkjc-1',
  leagueCode: 'I1',
  tournamentCode: 'I1',
  tournamentName: '意甲',
  kickOffTime: _now.add(const Duration(hours: 6)),
  status: 'PREEVENT',
  homeTeam: '博洛尼亞',
  awayTeam: '拉素',
  homeTeamEnglish: 'Bologna',
  awayTeamEnglish: 'Lazio',
  cornerLines: lines,
);

Widget _section({
  required List<HkjcMarketLine> lines,
  void Function(HkjcFootballFixture, HkjcCornerRecommendation)? onAdd,
}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        HkjcCornerSection(
          snapshot: HkjcFootballSnapshot(
            capturedAt: _now,
            fixtures: [_fixture(lines)],
          ),
          leagueCode: 'I1',
          loading: false,
          onRefresh: () async {},
          onAddSimulation: onAdd,
        ),
      ],
    ),
  ),
);

SimulationDraft _draft({bool recommended = true, double odds = 2.0}) =>
    SimulationDraft(
      sport: 'football',
      marketType: 'corners',
      matchId: 'hkjc-1',
      leagueCode: 'I1',
      leagueName: '意甲',
      homeTeam: '博洛尼亞',
      awayTeam: '拉素',
      startTime: _now.add(const Duration(hours: 6)),
      selectionLabel: '角球 9.5 大',
      direction: 'over',
      line: 9.5,
      odds: odds,
      modelProbability: 0.58,
      marketProbability: 0.5,
      edge: 0.16,
      confidence: 0.52,
      confidenceLabel: '中',
      recommended: recommended,
      stakeFraction: 0.01,
      marketSource: '馬會足球角球盤',
      marketCapturedAt: _now,
    );

void main() {
  testWidgets('a cleared pick offers the simulated account', (tester) async {
    HkjcCornerRecommendation? offered;
    await tester.pumpWidget(
      _section(lines: _mispriced, onAdd: (_, pick) => offered = pick),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('博洛尼亞'));
    await tester.pumpAndSettle();

    expect(find.text('加入模擬戶口'), findsOneWidget);

    await tester.ensureVisible(find.text('加入模擬戶口'));
    await tester.tap(find.text('加入模擬戶口'));
    await tester.pumpAndSettle();

    expect(offered, isNotNull);
    expect(offered!.odds, greaterThan(1));
  });

  testWidgets('an observed fixture offers no bet at all', (tester) async {
    await tester.pumpWidget(_section(lines: _agreeing, onAdd: (_, _) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('博洛尼亞'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不建議'), findsWidgets);
    expect(find.text('加入模擬戶口'), findsNothing);
  });

  testWidgets('no entry point exists when the page passes no handler', (
    tester,
  ) async {
    await tester.pumpWidget(_section(lines: _mispriced));
    await tester.pumpAndSettle();
    await tester.tap(find.text('博洛尼亞'));
    await tester.pumpAndSettle();

    expect(find.text('加入模擬戶口'), findsNothing);
  });

  group('stake sheet', () {
    // The real page opens the sheet as a modal route, so it is pumped the same
    // way here: confirming dismisses that route.
    Future<void> open(
      WidgetTester tester, {
      required ValueChanged<double> onConfirm,
      SimulationDraft? draft,
      double available = 10000,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => SimulationSheet(
                    draft: draft ?? _draft(),
                    balance: 10000,
                    available: available,
                    onConfirm: onConfirm,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the published line and price as read-only', (
      tester,
    ) async {
      await open(tester, onConfirm: (_) {});

      expect(find.text('推介盤口（不可修改）'), findsOneWidget);
      expect(find.text('角球 9.5 大'), findsOneWidget);
      // The HKJC price, and the same figure again as the vig-free fair odds.
      expect(find.text('2.00'), findsNWidgets(2));
      expect(find.text('58.0%'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.textContaining('賠率來源：馬會足球角球盤'), findsOneWidget);
      // Only the stake is editable.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('confirms the stake the user typed', (tester) async {
      final stakes = <double>[];
      await open(tester, onConfirm: stakes.add);

      await tester.enterText(find.byType(TextField), '250');
      await tester.pump();
      await tester.ensureVisible(find.text('確認加入模擬戶口'));
      await tester.tap(find.text('確認加入模擬戶口'));
      await tester.pumpAndSettle();

      expect(stakes, [250]);
    });

    testWidgets('refuses a stake beyond the available balance', (tester) async {
      final stakes = <double>[];
      await open(tester, onConfirm: stakes.add, available: 100);

      await tester.enterText(find.byType(TextField), '500');
      await tester.pump();

      expect(find.text('超出可用餘額'), findsOneWidget);
      await tester.ensureVisible(find.text('確認加入模擬戶口'));
      await tester.tap(find.text('確認加入模擬戶口'));
      await tester.pumpAndSettle();
      expect(stakes, isEmpty);
    });

    testWidgets('takes no record once the event has started', (tester) async {
      final stakes = <double>[];
      await open(
        tester,
        onConfirm: stakes.add,
        draft: SimulationDraft(
          sport: 'football',
          marketType: 'corners',
          matchId: 'hkjc-1',
          leagueCode: 'I1',
          leagueName: '意甲',
          homeTeam: '博洛尼亞',
          awayTeam: '拉素',
          startTime: DateTime.now().subtract(const Duration(minutes: 5)),
          selectionLabel: '角球 9.5 大',
          direction: 'over',
          line: 9.5,
          odds: 2,
          modelProbability: 0.58,
          marketProbability: 0.5,
          edge: 0.16,
          confidence: 0.5,
          confidenceLabel: '中',
          recommended: true,
        ),
      );

      await tester.enterText(find.byType(TextField), '100');
      await tester.pump();

      expect(find.text('此場已開賽，不再接受新的模擬記錄。'), findsOneWidget);
      await tester.ensureVisible(find.text('確認加入模擬戶口'));
      await tester.tap(find.text('確認加入模擬戶口'));
      await tester.pumpAndSettle();
      expect(stakes, isEmpty);
    });
  });

  group('account page', () {
    Widget page({
      required VoidCallback onClear,
      List<SimulatedTrade> trades = const [],
    }) => MaterialApp(
      home: Scaffold(
        body: SimulationAccount(
          trades: trades,
          bankroll: 10000,
          onShareTrade: (_) {},
          onShareAll: () {},
          onExport: () {},
          onImport: () {},
          onClear: onClear,
          onBankrollChanged: (_) {},
        ),
      ),
    );

    testWidgets('states that the units are virtual', (tester) async {
      await tester.pumpWidget(page(onClear: () {}));
      await tester.pumpAndSettle();

      expect(find.text('戶口價值（虛擬）'), findsOneWidget);
      expect(find.text('虛擬研究記錄 · 不涉及真實資金'), findsOneWidget);
      expect(find.textContaining('不提供真實投注、付款或轉帳'), findsOneWidget);
      expect(find.text('尚未有模擬下注'), findsOneWidget);
    });

    testWidgets('clearing needs a confirmation that says it is final', (
      tester,
    ) async {
      var cleared = 0;
      await tester.pumpWidget(
        page(
          onClear: () => cleared++,
          trades: [_draft().toTrade(stake: 100, now: _now)],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('刪除全部'));
      await tester.pumpAndSettle();
      expect(find.textContaining('不可復原'), findsOneWidget);

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(cleared, 0);

      await tester.tap(find.text('刪除全部'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '刪除全部'));
      await tester.pumpAndSettle();
      expect(cleared, 1);
    });
  });
}
