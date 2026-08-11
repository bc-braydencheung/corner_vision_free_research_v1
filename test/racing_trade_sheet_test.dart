import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/widgets/racing_trade_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains why racing simulation confirmation is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacingTradeSheet(
            race: _race(DateTime.now().toUtc().add(const Duration(days: 1))),
            runner: _runner,
            modelVersion: 'test',
            availableBalance: 1000,
            onBuy: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('按目前賠率計算的保守 EV 未達+5%安全邊際，不能建立模擬記錄。'), findsOneWidget);
    final confirmButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '確認獨贏模擬買入'),
    );
    expect(confirmButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '6.00');
    await tester.pump();

    expect(find.text('保守 EV 至少+5%，可加入不可修改的模擬記錄。'), findsOneWidget);
    final enabledButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '確認獨贏模擬買入'),
    );
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('explains when the race has already started', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RacingTradeSheet(
            race: _race(
              DateTime.now().toUtc().subtract(const Duration(days: 1)),
            ),
            runner: _runner,
            modelVersion: 'test',
            availableBalance: 1000,
            onBuy: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('賽事已開跑或完成，不能建立新的模擬記錄。'), findsOneWidget);
  });
}

RacingRace _race(DateTime startTime) => RacingRace(
  raceId: 'HK:test',
  date: startTime,
  startTime: startTime,
  venue: '沙田',
  raceNumber: 1,
  raceName: '測試讓賽',
  distanceMetres: 1200,
  surface: 'TURF',
  course: '"A" Course',
  going: 'GOOD',
  raceClass: '4',
  runners: const [_runner],
);

const _runner = RacingRunner(
  horseId: 'K001',
  horseName: '測試馬',
  horseNameEnglish: 'TEST HORSE',
  horseNameChinese: '測試馬',
  number: 1,
  draw: 3,
  jockey: '測試騎師',
  trainer: '測試練馬師',
  winProbability: 0.2,
  placeProbability: 0.5,
  fairWinOdds: 5,
  fairPlaceOdds: 2,
  confidence: 'medium',
  confidenceScore: 0.7,
  recommendation: 'model-view',
  factors: ['近仗名次走勢較佳'],
);
