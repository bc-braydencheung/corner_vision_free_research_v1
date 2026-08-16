import 'package:edgewise/marksix_lab/lab_state.dart';
import 'package:edgewise/marksix_lab/lab_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('disruptive mode gates on age before showing the lab', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MarkSixLabView())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('18'), findsWidgets);
    expect(find.text('鑄造'), findsNothing);

    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.text('鑄造'), findsOneWidget);
    expect(find.text('反人群'), findsOneWidget);
  });

  test('resampling draws a new synthetic dataset, rebuilding keeps it', () {
    final state = LabState();
    state.regenerateSynthetic();
    final seed = state.syntheticSeed;
    final first = state.history.first.numbers;

    state.regenerateSynthetic();
    expect(state.syntheticSeed, seed);
    expect(state.history.first.numbers, first);

    state.regenerateSynthetic(newSeed: true);
    expect(state.syntheticSeed, isNot(seed));
    expect(state.history.first.numbers, isNot(first));
    expect(state.historyNote, contains('種子 0x'));
  });
}
