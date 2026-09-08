import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/widgets/hkjc_corner_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kick-off gating reads the wall clock, so the fixture sits ahead of it.
final _now = DateTime.now().toUtc();
final _kickOff = _now.add(const Duration(hours: 6));

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

FootballOddsSnapshot _quote({
  required Duration before,
  required double over,
  required double under,
}) => FootballOddsSnapshot(
  matchId: 'hkjc-1',
  capturedAt: _kickOff.subtract(before),
  source: 'hkjc-chl',
  line: 9.5,
  overOdds: over,
  underOdds: under,
);

Widget _section(List<FootballOddsSnapshot> history) => MaterialApp(
  home: Scaffold(
    body: ListView(
      children: [
        HkjcCornerSection(
          snapshot: HkjcFootballSnapshot(
            capturedAt: _now,
            fixtures: [
              HkjcFootballFixture(
                matchId: 'hkjc-1',
                frontEndId: 'hkjc-1',
                leagueCode: 'I1',
                tournamentCode: 'I1',
                tournamentName: '意甲',
                kickOffTime: _kickOff,
                status: 'PREEVENT',
                homeTeam: '博洛尼亞',
                awayTeam: '拉素',
                homeTeamEnglish: 'Bologna',
                awayTeamEnglish: 'Lazio',
                cornerLines: _lines,
              ),
            ],
          ),
          leagueCode: 'I1',
          loading: false,
          onRefresh: () async {},
          oddsHistory: history,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('a thin history says so instead of showing a flat market', (
    tester,
  ) async {
    await tester.pumpWidget(_section(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.text('博洛尼亞'));
    await tester.pumpAndSettle();

    expect(find.textContaining('盤口移動 快照未足兩個時點'), findsOneWidget);
  });

  testWidgets('a market that drifted to the over side reports the move', (
    tester,
  ) async {
    await tester.pumpWidget(
      _section([
        _quote(before: const Duration(hours: 26), over: 2.10, under: 1.75),
        _quote(before: const Duration(hours: 7), over: 1.95, under: 1.90),
        _quote(before: const Duration(hours: 2), over: 1.80, under: 2.00),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('博洛尼亞'));
    await tester.pumpAndSettle();

    expect(find.textContaining('盤口移動 9.5'), findsOneWidget);
    expect(find.textContaining('大 +'), findsWidgets);
    expect(find.textContaining('單向走向大盤'), findsOneWidget);
  });
}
