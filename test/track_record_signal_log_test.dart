import 'package:edgewise/models/signal_change.dart';
import 'package:edgewise/services/track_record.dart';
import 'package:edgewise/widgets/track_record_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _matchDate = DateTime.utc(2026, 8, 29, 2, 45);

TrackRecordEntry _entry() => TrackRecordEntry(
  matchId: 'hkjc-1',
  leagueName: '意甲',
  homeTeam: 'AC米蘭',
  awayTeam: '威尼斯',
  line: 9.5,
  matchDate: _matchDate,
  capturedAt: DateTime.utc(2026, 8, 27, 9, 41),
  direction: 'low',
  modelProbability: 0.603,
  marketProbability: 0.538,
  takenOdds: 1.72,
  takenAt: DateTime.utc(2026, 8, 27, 9, 41),
  edge: 0.0376,
  recommended: true,
);

SignalChange _change({
  required DateTime capturedAt,
  required double modelProbability,
  required double edge,
  required bool recommended,
  String matchId = 'hkjc-1',
}) => SignalChange(
  matchId: matchId,
  leagueCode: 'I1',
  leagueName: '意甲',
  homeTeam: 'AC米蘭',
  awayTeam: '威尼斯',
  matchDate: _matchDate,
  capturedAt: capturedAt,
  line: 9.5,
  direction: 'low',
  odds: 1.72,
  modelProbability: modelProbability,
  marketProbability: 0.538,
  edge: edge,
  requiredEdge: 0.02,
  recommended: recommended,
);

Widget _app(List<SignalChange> log) => MaterialApp(
  home: Scaffold(
    body: TrackRecordView(
      report: TrackRecordReport(
        entries: [_entry()],
        skipped: const {},
        recommended: 1,
        settled: 0,
        hits: 0,
        brier: 0,
        marketBrier: 0,
        brierSamples: 0,
        meanClosingLineValue: 0,
        beatClosingRate: 0,
        clvSamples: 0,
        netUnits: 0,
        maximumDrawdownUnits: 0,
      ),
      signalLog: log,
      onShare: () {},
    ),
  ),
);

void main() {
  testWidgets('a withdrawn pick shows both states, newest first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        _change(
          capturedAt: DateTime.utc(2026, 8, 27, 9, 41),
          modelProbability: 0.603,
          edge: 0.0376,
          recommended: true,
        ),
        _change(
          capturedAt: DateTime.utc(2026, 8, 27, 20, 15),
          modelProbability: 0.579,
          edge: -0.004,
          recommended: false,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('訊號變動'), findsOneWidget);
    final observed = tester.getTopLeft(find.textContaining('觀察 細9.5')).dy;
    final recommended = tester.getTopLeft(find.textContaining('推介 細9.5')).dy;
    expect(observed, lessThan(recommended));
    expect(find.textContaining('模型 57.9%'), findsOneWidget);
    expect(find.textContaining('EV -0.40%'), findsOneWidget);
  });

  testWidgets('a single reading adds no history block', (tester) async {
    await tester.pumpWidget(
      _app([
        _change(
          capturedAt: DateTime.utc(2026, 8, 27, 9, 41),
          modelProbability: 0.603,
          edge: 0.0376,
          recommended: true,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('訊號變動'), findsNothing);
  });

  testWidgets('another fixture\'s readings never reach this row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        _change(
          capturedAt: DateTime.utc(2026, 8, 27, 9, 41),
          modelProbability: 0.603,
          edge: 0.0376,
          recommended: true,
          matchId: 'other',
        ),
        _change(
          capturedAt: DateTime.utc(2026, 8, 27, 20, 15),
          modelProbability: 0.579,
          edge: -0.004,
          recommended: false,
          matchId: 'other',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('訊號變動'), findsNothing);
  });
}
