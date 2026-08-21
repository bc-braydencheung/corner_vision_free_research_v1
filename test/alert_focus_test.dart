import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/widgets/hkjc_corner_section.dart';
import 'package:edgewise/widgets/scroll_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _lines = [
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

HkjcFootballFixture _fixture(int index) => HkjcFootballFixture(
  matchId: 'm$index',
  frontEndId: 'm$index',
  leagueCode: 'I1',
  tournamentCode: 'I1',
  tournamentName: '意甲',
  kickOffTime: DateTime.utc(2026, 8, 21, 12).add(Duration(hours: index)),
  status: 'PREEVENT',
  homeTeam: '主隊$index',
  awayTeam: '客隊$index',
  homeTeamEnglish: 'Home $index',
  awayTeamEnglish: 'Away $index',
  cornerLines: _lines,
);

/// Mirrors the real layout: the fixtures sit inside one tall card, so a card
/// far below the fold is laid out even before the list scrolls to it.
Widget _list({required ScrollController controller, required Widget child}) =>
    MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            Column(children: [const SizedBox(height: 2000), child]),
          ],
        ),
      ),
    );

bool _visible(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  final viewport = tester.getRect(find.byType(Scaffold));
  return rect.top < viewport.bottom && rect.bottom > viewport.top;
}

void main() {
  testWidgets('a focused card reports itself into view', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _list(
        controller: controller,
        child: const ScrollFocusTarget(
          focused: true,
          child: SizedBox(height: 120, child: Text('目標')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(1000));
    expect(_visible(tester, find.text('目標')), isTrue);
  });

  testWidgets('an unfocused card never moves the list', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _list(
        controller: controller,
        child: const ScrollFocusTarget(
          focused: false,
          child: SizedBox(height: 120, child: Text('目標')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, 0);
  });

  testWidgets('becoming focused later still brings the card up', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget build(bool focused) => _list(
      controller: controller,
      child: ScrollFocusTarget(
        focused: focused,
        child: const SizedBox(height: 120, child: Text('目標')),
      ),
    );

    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);

    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(1000));
    expect(_visible(tester, find.text('目標')), isTrue);
  });

  testWidgets('a tapped pick lands on its own fixture, not just the league', (
    tester,
  ) async {
    final fixtures = [for (var index = 0; index < 8; index++) _fixture(index)];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              HkjcCornerSection(
                snapshot: HkjcFootballSnapshot(
                  capturedAt: DateTime.utc(2026, 8, 20, 12),
                  fixtures: fixtures,
                ),
                leagueCode: 'I1',
                loading: false,
                onRefresh: () async {},
                focusMatchId: 'm7',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_visible(tester, find.text('主隊7')), isTrue);
    expect(_visible(tester, find.text('主隊0')), isFalse);
  });
}
