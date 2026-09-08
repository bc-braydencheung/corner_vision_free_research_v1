import 'package:edgewise/theme/app_theme.dart';
import 'package:edgewise/widgets/motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = '未顯著勝過基準率（Brier 技巧 4.4%）：不應視為有預測力';

void main() {
  testWidgets('a long label wraps inside a narrow card', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlowPill(label: _long, color: AppPalette.amber, dense: true),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final pill = tester.getSize(find.byType(GlowPill));
    expect(pill.width, lessThanOrEqualTo(360 - 32));
    // Wrapping, not clipping: the pill grows taller than a single line.
    expect(pill.height, greaterThan(20));
  });

  testWidgets('an unbounded parent keeps the intrinsic width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                GlowPill(label: _long, color: AppPalette.cyan, dense: true),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text(_long), findsOneWidget);
  });
}
