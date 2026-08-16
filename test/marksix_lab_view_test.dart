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
}
