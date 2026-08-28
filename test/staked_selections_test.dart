import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/simulated_trade.dart';
import 'package:edgewise/models/simulation_draft.dart';
import 'package:edgewise/services/corner_alerts.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/simulation_entry.dart';
import 'package:edgewise/services/staked_selections.dart';
import 'package:edgewise/widgets/alert_summary_card.dart';
import 'package:edgewise/widgets/hkjc_corner_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kick-off gating is measured against the wall clock, so fixtures sit ahead
/// of it rather than on a fixed date.
final _now = DateTime.now().toUtc();

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

HkjcFootballFixture _fixture() => HkjcFootballFixture(
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
  cornerLines: _mispriced,
);

SimulationDraft _cornerDraft({
  String matchId = 'hkjc-1',
  String direction = 'over',
  double line = 9.5,
}) => SimulationDraft(
  sport: 'football',
  marketType: 'corners',
  matchId: matchId,
  leagueCode: 'I1',
  leagueName: '意甲',
  homeTeam: '博洛尼亞',
  awayTeam: '拉素',
  startTime: _now.add(const Duration(hours: 6)),
  selectionLabel: '角球 $line ${direction == 'over' ? '大' : '細'}',
  direction: direction,
  line: line,
  odds: 2,
  modelProbability: 0.58,
  marketProbability: 0.5,
  edge: 0.16,
  confidence: 0.52,
  confidenceLabel: '中',
  recommended: true,
  stakeFraction: 0.01,
);

SimulationDraft _racingDraft({String selectionId = 'horse-1'}) =>
    SimulationDraft(
      sport: 'racing',
      marketType: 'win',
      matchId: 'race-1',
      leagueCode: 'HK',
      leagueName: '香港賽馬',
      homeTeam: '馬名',
      awayTeam: '沙田第1場',
      startTime: _now.add(const Duration(hours: 3)),
      selectionLabel: '獨贏 1 號',
      direction: 'win',
      line: 0,
      odds: 6,
      modelProbability: 0.2,
      marketProbability: 0.15,
      edge: 0.2,
      confidence: 0.5,
      confidenceLabel: '中',
      recommended: true,
      selectionId: selectionId,
      stakeFraction: 0.01,
    );

SimulatedTrade _trade(SimulationDraft draft) =>
    draft.toTrade(stake: 100, now: _now);

Widget _section({
  required StakedSelections staked,
  void Function(HkjcFootballFixture, HkjcCornerRecommendation)? onAdd,
}) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        HkjcCornerSection(
          snapshot: HkjcFootballSnapshot(
            capturedAt: _now,
            fixtures: [_fixture()],
          ),
          leagueCode: 'I1',
          loading: false,
          onRefresh: () async {},
          onAddSimulation: onAdd ?? (_, _) {},
          staked: staked,
        ),
      ],
    ),
  ),
);

void main() {
  group('staked keys', () {
    test('the same market, side and line counts as already recorded', () {
      final staked = StakedSelections.of([_trade(_cornerDraft())]);

      expect(staked.holdsDraft(_cornerDraft()), isTrue);
      expect(staked.holdsMatch('hkjc-1'), isTrue);
    });

    test('a moved line or the other side stays recordable', () {
      final staked = StakedSelections.of([_trade(_cornerDraft())]);

      expect(staked.holdsDraft(_cornerDraft(line: 10.5)), isFalse);
      expect(staked.holdsDraft(_cornerDraft(direction: 'under')), isFalse);
      // The fixture itself still carries a bet, which is what the tag says.
      expect(staked.holdsMatch('hkjc-1'), isTrue);
    });

    test('another fixture is untouched', () {
      final staked = StakedSelections.of([_trade(_cornerDraft())]);

      expect(staked.holdsDraft(_cornerDraft(matchId: 'hkjc-2')), isFalse);
      expect(staked.holdsMatch('hkjc-2'), isFalse);
    });

    test('runners of one race are told apart by their own id', () {
      final staked = StakedSelections.of([_trade(_racingDraft())]);

      expect(staked.holdsDraft(_racingDraft()), isTrue);
      expect(staked.holdsDraft(_racingDraft(selectionId: 'horse-2')), isFalse);
      expect(staked.holdsMatch('race-1'), isTrue);
    });

    test('an empty account holds nothing', () {
      expect(StakedSelections.empty.holdsDraft(_cornerDraft()), isFalse);
      expect(StakedSelections.of(const []).holdsMatch('hkjc-1'), isFalse);
    });
  });

  group('fixture card', () {
    /// The pick the card publishes, read off the same model the tile uses so
    /// the ledger row matches the side and line the card printed.
    SimulationDraft offered() {
      final pick = const HkjcCornerModel().assess(_fixture())?.recommendation;
      expect(pick, isNotNull);
      return cornerSimulationDraft(
        leagueCode: 'I1',
        leagueName: '意甲',
        fixture: _fixture(),
        pick: pick!,
        recommended: true,
      );
    }

    testWidgets('a recorded pick is marked and no longer offered', (
      tester,
    ) async {
      final draft = offered();
      await tester.pumpWidget(
        _section(staked: StakedSelections.of([_trade(draft)])),
      );
      await tester.pumpAndSettle();

      // Collapsed, the fixture already states that a bet exists.
      expect(find.text('已入模擬戶口'), findsOneWidget);

      await tester.tap(find.text('博洛尼亞'));
      await tester.pumpAndSettle();

      expect(find.text('加入模擬戶口'), findsNothing);
      expect(find.text('已加入模擬戶口'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '已加入模擬戶口'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a bet on another side leaves this pick recordable', (
      tester,
    ) async {
      final draft = offered();
      final other = _cornerDraft(
        direction: draft.direction == 'over' ? 'under' : 'over',
        line: draft.line,
      );
      await tester.pumpWidget(
        _section(staked: StakedSelections.of([_trade(other)])),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('博洛尼亞'));
      await tester.pumpAndSettle();

      expect(find.text('加入模擬戶口'), findsOneWidget);
      // The fixture tag is not shown once the card is open.
      expect(find.text('已加入模擬戶口'), findsNothing);
    });
  });

  group('today\'s picks card', () {
    List<CornerAlert> alerts() => buildCornerAlerts(
      snapshot: HkjcFootballSnapshot(capturedAt: _now, fixtures: [_fixture()]),
      leagueNames: const {'I1': '意甲'},
      asOf: _now,
    );

    Widget card(StakedSelections staked) => MaterialApp(
      home: Scaffold(
        body: AlertSummaryCard(
          alerts: alerts(),
          loading: false,
          onShare: () {},
          staked: staked,
        ),
      ),
    );

    testWidgets('marks a pick the simulated account already holds', (
      tester,
    ) async {
      final alert = alerts().single;
      final draft = simulationDraftFromAlert(alert);
      expect(draft, isNotNull);

      await tester.pumpWidget(card(StakedSelections.empty));
      await tester.pumpAndSettle();
      expect(find.text('已入模擬戶口'), findsNothing);

      await tester.pumpWidget(card(StakedSelections.of([_trade(draft!)])));
      await tester.pumpAndSettle();
      expect(find.text('已入模擬戶口'), findsOneWidget);
    });
  });
}
