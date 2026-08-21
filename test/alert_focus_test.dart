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
  // The race card and the fixture card share this rule, so the race path keeps
  // its regression cover without pumping the whole racing page.
  group('reopening the card a pick points at', () {
    test('a repeated tap on the same target reopens it', () {
      expect(
        shouldReopenForFocus(
          focused: true,
          wasFocused: true,
          request: 2,
          previousRequest: 1,
        ),
        isTrue,
      );
    });

    test('a first tap on a new target opens it', () {
      expect(
        shouldReopenForFocus(
          focused: true,
          wasFocused: false,
          request: 1,
          previousRequest: 1,
        ),
        isTrue,
      );
    });

    test('a pick pointing elsewhere never opens this card', () {
      expect(
        shouldReopenForFocus(
          focused: false,
          wasFocused: true,
          request: 3,
          previousRequest: 2,
        ),
        isFalse,
      );
    });

    test('an unrelated rebuild leaves a collapsed card alone', () {
      expect(
        shouldReopenForFocus(
          focused: true,
          wasFocused: true,
          request: 4,
          previousRequest: 4,
        ),
        isFalse,
      );
    });
  });

  group('what a tapped pick asks for', () {
    test('tapping a fixture pick targets it with a fresh request', () {
      final focus = AlertFocus.none.onFixture('m7');

      expect(focus.matchId, 'm7');
      expect(focus.raceId, isNull);
      expect(focus.request, 1);
    });

    test('tapping the same pick twice still counts as a new request', () {
      final focus = AlertFocus.none.onFixture('m7').onFixture('m7');

      expect(focus.matchId, 'm7');
      expect(focus.request, 2);
    });

    test('a racing pick drops any fixture target', () {
      final focus = AlertFocus.none.onFixture('m7').onRace('r3');

      expect(focus.raceId, 'r3');
      expect(focus.matchId, isNull);
      expect(focus.request, 2);
    });

    test('browsing forgets the target so no league jumps by itself', () {
      final focus = AlertFocus.none.onFixture('m7').browsing;

      expect(focus.matchId, isNull);
      expect(focus.raceId, isNull);
      // Kept, so a later tap on the same pick is still a new request.
      expect(focus.request, 1);
    });

    test('a pick after browsing navigates again', () {
      final focus = AlertFocus.none.onFixture('m7').browsing.onFixture('m7');

      expect(focus.matchId, 'm7');
      expect(focus.request, 2);
    });
  });

  testWidgets('returning to a league without a pick never jumps', (
    tester,
  ) async {
    final fixtures = [for (var index = 0; index < 8; index++) _fixture(index)];
    Widget build({required String leagueCode, String? focusMatchId}) =>
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                HkjcCornerSection(
                  snapshot: HkjcFootballSnapshot(
                    capturedAt: DateTime.utc(2026, 8, 20, 12),
                    fixtures: fixtures,
                  ),
                  leagueCode: leagueCode,
                  loading: false,
                  onRefresh: () async {},
                  focusMatchId: focusMatchId,
                  focusRequest: 1,
                ),
              ],
            ),
          ),
        );

    await tester.pumpWidget(build(leagueCode: 'I1', focusMatchId: 'm7'));
    await tester.pumpAndSettle();
    expect(_visible(tester, find.text('主隊7')), isTrue);

    // The user browses to another league and back, without tapping the pick.
    await tester.pumpWidget(build(leagueCode: 'E0'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(leagueCode: 'I1'));
    await tester.pumpAndSettle();

    expect(_visible(tester, find.text('主隊7')), isFalse);
  });

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

  testWidgets('tapping the same pick twice navigates again', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    Widget build(int request) => _list(
      controller: controller,
      child: ScrollFocusTarget(
        focused: true,
        request: request,
        child: const SizedBox(height: 120, child: Text('目標')),
      ),
    );

    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    expect(_visible(tester, find.text('目標')), isTrue);

    // The user scrolls away, then taps the very same pick again.
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(_visible(tester, find.text('目標')), isFalse);

    await tester.pumpWidget(build(2));
    await tester.pumpAndSettle();
    expect(_visible(tester, find.text('目標')), isTrue);
  });

  testWidgets('a repeated pick reopens the fixture it points at', (
    tester,
  ) async {
    Widget build(int request) => MaterialApp(
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
              focusMatchId: 'm0',
              focusRequest: request,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(build(1));
    await tester.pumpAndSettle();
    expect(find.text('盤口'), findsOneWidget);

    // The user collapses the card by hand, then taps the same pick again.
    await tester.tap(find.text('主隊0'));
    await tester.pumpAndSettle();
    expect(find.text('盤口'), findsNothing);

    await tester.pumpWidget(build(2));
    await tester.pumpAndSettle();
    expect(find.text('盤口'), findsOneWidget);
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
