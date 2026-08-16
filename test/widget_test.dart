import 'package:edgewise/main.dart';
import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/services/data_service.dart';
import 'package:edgewise/services/football_mobile_service.dart';
import 'package:edgewise/widgets/prediction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows the multi-sport dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(EdgeWiseApp(dataService: _FakeDataService()));
    await tester.pump();
    await tester.pump();

    expect(find.text('睿測'), findsOneWidget);
    expect(find.text('足球'), findsOneWidget);
    expect(find.text('賽馬'), findsOneWidget);
    expect(find.text('英超模型健康度'), findsNothing);
    expect(find.text('模擬戶口'), findsNothing);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('馬會賽程 · 角球大細'), findsOneWidget);

    await tester.tap(find.text('研究健康'));
    await tester.pump();
    expect(find.text('研究健康中心'), findsOneWidget);
    expect(find.text('重新訓練統計模型'), findsOneWidget);
    await tester.drag(find.text('研究健康中心'), const Offset(0, -400));
    await tester.pump();
    expect(find.text('免費資料來源'), findsOneWidget);
    expect(find.textContaining('需匯入用戶下載檔'), findsOneWidget);

    await tester.tap(find.text('分析'));
    await tester.pump();
    await tester.tap(find.text('賽馬'));
    await tester.pump();
    expect(find.text('香港賽馬個人研究模型'), findsOneWidget);
    expect(find.text('測試馬'), findsOneWidget);
    expect(find.text('TEST HORSE'), findsOneWidget);
    expect(find.textContaining('獨贏 20.0%'), findsOneWidget);
    expect(find.text('No bet'), findsWidgets);
    expect(find.text('信心不足'), findsOneWidget);
  });

  testWidgets('disables football simulation without actual market data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PredictionCard(
          prediction: MatchPrediction(
            matchId: 'E0:2027-01-01:Alpha:Beta',
            leagueCode: 'E0',
            leagueName: '英超',
            mode: 'forecast',
            date: DateTime.utc(2027),
            homeTeam: 'Alpha',
            homeTeamCn: '',
            awayTeam: 'Beta',
            awayTeamCn: '',
            expectedHomeCorners: 5,
            expectedAwayCorners: 5,
            expectedTotalCorners: 10,
            actualTotalCorners: null,
            interval80: const [6, 14],
            confidence: 'medium',
            confidenceScore: 0.7,
            markets: const [
              MarketPrediction(
                line: 9.5,
                overProbability: 0.55,
                underProbability: 0.45,
                fairOverOdds: 1.82,
                fairUnderOdds: 2.22,
              ),
            ],
            totalDistribution: const [1],
            factors: const [],
            recommendation: 'model-view',
            forecastStage: 'T-24h free-data',
            dataQuality: 0.8,
            modelStability: 0.7,
          ),
          onSimulate: null,
        ),
      ),
    );

    expect(find.textContaining('No bet：目前賽事沒有'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}

class _FakeDataService extends DataService {
  const _FakeDataService()
    : super(checkDirectResults: false, checkRacingUpdates: false);

  @override
  Future<ForecastLoadResult> load() async {
    return ForecastLoadResult(
      data: ForecastData(
        dataVersion: 'test',
        generatedAt: DateTime.utc(2026),
        leagues: [
          LeagueForecastData(
            code: 'E0',
            name: '英超',
            supportName: '英冠',
            status: '測試資料',
            model: const ModelSummary(
              selectedCandidate: 'poisson_recent',
              selectedCandidateLabel: 'Recency-Weighted Count Model',
              trainedThrough: '2026-05-01',
              firstSeason: '2000/01',
              lastSeason: '2025/26',
              trainingMatches: 100,
              supportMatches: 100,
              supportName: '英冠',
              validationMatches: 50,
              holdoutMatches: 20,
              maeTotalCorners: 2.7,
              baselineMaeHoldout: 2.8,
              maeSkillVsDynamicPercent: 1,
              withinTwoHoldout: 0.45,
              brierOver9_5: 0.24,
              brierSkillOver9_5Percent: 1,
              calibrationErrorOver9_5: 0.02,
            ),
            forecasts: const [],
            recentBacktests: const [],
          ),
        ],
        settlementResults: const [],
        racing: RacingSummary(
          available: true,
          status: '個人研究模型已載入',
          sourceNotice: '低頻率本機快取，只供個人研究',
          model: const RacingModelSummary(
            selectedCandidate: 'dynamic',
            trainingRaces: 100,
            holdoutRaces: 20,
            winLogLoss: 2.1,
          ),
          races: [
            RacingRace(
              raceId: 'HK:2027-01-01:ST:1',
              date: DateTime.utc(2027),
              startTime: DateTime.utc(2027, 1, 1, 6),
              venue: '沙田',
              raceNumber: 1,
              raceName: '測試讓賽',
              distanceMetres: 1200,
              surface: 'TURF',
              course: '"A" Course',
              going: 'GOOD',
              raceClass: '4',
              runners: const [
                RacingRunner(
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
                ),
                RacingRunner(
                  horseId: 'K002',
                  horseName: '資料不足馬',
                  horseNameEnglish: 'LIMITED DATA',
                  horseNameChinese: '資料不足馬',
                  number: 2,
                  draw: 8,
                  jockey: '測試騎師',
                  trainer: '測試練馬師',
                  winProbability: 0.05,
                  placeProbability: 0.2,
                  fairWinOdds: 20,
                  fairPlaceOdds: 5,
                  confidence: 'avoid',
                  confidenceScore: 0.4,
                  recommendation: 'no-prediction',
                  factors: ['模型資料不足'],
                ),
              ],
            ),
          ],
        ),
        disclaimer: '只供統計研究',
      ),
      isRemote: false,
      message: '測試資料已載入',
      footballStatus: const FootballSyncStatus(
        message: '已加入 5 場新足球賽果 · 新賽果尚待重新訓練',
        hasNewResults: true,
        newMatches: 5,
        fixturesChanged: true,
        datasetVersion: 'test-football',
        latestResults: {'英超': '2026-07-13'},
      ),
    );
  }
}
