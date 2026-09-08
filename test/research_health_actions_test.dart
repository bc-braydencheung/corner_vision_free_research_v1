import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/widgets/research_health_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ForecastData _data() => ForecastData(
  dataVersion: 'test',
  generatedAt: DateTime.utc(2026),
  leagues: const [],
  settlementResults: const [],
  racing: const RacingSummary(
    available: false,
    status: '測試',
    sourceNotice: '測試',
    model: RacingModelSummary(
      selectedCandidate: 'dynamic',
      trainingRaces: 0,
      holdoutRaces: 0,
      winLogLoss: 0,
    ),
    races: [],
  ),
  disclaimer: '只供統計研究',
);

Widget _view({
  required bool collectingOdds,
  required bool runningAblation,
  required bool footballSyncing,
  required VoidCallback onTap,
}) => MaterialApp(
  home: Scaffold(
    body: ResearchHealthView(
      data: _data(),
      footballStatus: null,
      racingStatus: null,
      shadowHealth: ShadowHealth.empty,
      sourceErrors: const {},
      trades: const [],
      onExportReport: () async {},
      onExportBackup: () async {},
      onImportBackup: () async {},
      onDriveBackup: () async {},
      onDriveRestore: () async {},
      collectingOdds: collectingOdds,
      runningAblation: runningAblation,
      footballSyncing: footballSyncing,
      onCollectOdds: () async => onTap(),
      onRunAblation: () async => onTap(),
      onRefreshFootball: () async => onTap(),
      onTrainFootball: () async => onTap(),
    ),
  ),
);

/// The audit page is a long lazy list, so the cards under test are only built
/// when there is room for them on screen.
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('an idle maintenance button reports the press', (tester) async {
    var presses = 0;
    _tallScreen(tester);
    await tester.pumpWidget(
      _view(
        collectingOdds: false,
        runningAblation: false,
        footballSyncing: false,
        onTap: () => presses++,
      ),
    );
    for (final tooltip in const ['立即收集一次', '重新計算', '檢查歷史資料更新']) {
      expect(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    }
    await tester.tap(find.byTooltip('立即收集一次'));
    await tester.tap(find.byTooltip('重新計算'));
    await tester.tap(find.byTooltip('檢查歷史資料更新'));
    expect(presses, 3);
  });

  testWidgets('retraining stays reachable without new results', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      _view(
        collectingOdds: false,
        runningAblation: false,
        footballSyncing: false,
        onTap: () {},
      ),
    );
    expect(find.widgetWithText(FilledButton, '重新訓練統計模型'), findsOneWidget);
  });

  testWidgets('a running maintenance button spins instead of looking dead', (
    tester,
  ) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      _view(
        collectingOdds: true,
        runningAblation: true,
        footballSyncing: true,
        onTap: () {},
      ),
    );
    // One spinner per running action, so no press can look like no reaction.
    expect(find.byTooltip('正在進行…'), findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byTooltip('正在進行…'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNWidgets(3),
    );
    for (final button in tester.widgetList<IconButton>(
      find.descendant(
        of: find.byTooltip('正在進行…'),
        matching: find.byType(IconButton),
      ),
    )) {
      expect(button.onPressed, isNull);
    }
  });
}
