import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/widgets/back_to_top.dart';
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
    // The fixture that was asked for is the only one already open.
    expect(find.text('模型推介：不建議 · 各盤與模型一致'), findsOneWidget);
  });

  testWidgets('a fixture keeps only its verdict until it is opened', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              HkjcCornerSection(
                snapshot: HkjcFootballSnapshot(
                  capturedAt: DateTime.utc(2026, 8, 20, 12),
                  fixtures: [_fixture(0)],
                ),
                leagueCode: 'I1',
                loading: false,
                onRefresh: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('主隊0'), findsOneWidget);
    expect(find.text('不建議'), findsOneWidget);
    expect(find.text('盤口'), findsNothing);

    await tester.tap(find.text('主隊0'));
    await tester.pumpAndSettle();
    expect(find.text('盤口'), findsOneWidget);
    expect(find.text('不建議'), findsNothing);

    await tester.tap(find.text('主隊0'));
    await tester.pumpAndSettle();
    expect(find.text('盤口'), findsNothing);
  });

  testWidgets('back to top appears only after the page has moved', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackToTopScroller(
            builder: (context, controller) => ListView(
              controller: controller,
              children: [
                for (var index = 0; index < 40; index++)
                  SizedBox(height: 80, child: Text('列$index')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byType(FloatingActionButton);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1,
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('列0'), findsOneWidget);
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0,
    );
  });
}
