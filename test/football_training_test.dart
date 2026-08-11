import 'dart:io';
import 'dart:math';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:edgewise/services/football_training_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FootballStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('corner-football-test-');
    store = FootballStore(directory: directory);
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('restores the previous football dataset after corruption', () async {
    await store.saveDataset(_dataset(version: 'first'));
    await store.saveDataset(_dataset(version: 'second', extraMatch: true));
    await File(
      '${directory.path}/active-dataset.json.gz',
    ).writeAsString('corrupt');

    final restored = await store.loadDataset();

    expect(restored.datasetVersion, 'first');
    expect(restored.rows, hasLength(600));
  });

  test(
    'resumes five-league training and atomically activates a model',
    () async {
      final dataset = _dataset(version: 'football-training');
      await store.saveDataset(dataset);
      await store.markTrainingNeeded();
      final service = FootballTrainingService(store: store);
      final prepared = await service.prepare();
      await store.saveJob(
        FootballTrainingJob(
          id: prepared.id,
          datasetVersion: prepared.datasetVersion,
          status: 'training',
          stage: 'checkpoint',
          progress: 2,
          epoch: 5,
          updatedAt: DateTime.now(),
          checkpoint: {
            'leagueIndex': 0,
            'stageIndex': 0,
            'epoch': 5,
            'completedModels': <Object?>[],
            'featureMeans': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'featureScales': List<double>.filled(
              FootballMobileEngine.featureCount,
              1,
            ),
            'homeWeights': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'homeIntercept': log(5.5),
            'awayWeights': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'awayIntercept': log(5),
            'totalWeights': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'totalIntercept': log(10),
          },
        ),
      );

      expect(await service.run(), isTrue);
      final job = await store.loadJob();
      final model = await store.loadModel();

      expect(job?.status, 'completed');
      expect(job?.progress, 100);
      expect(model?.datasetVersion, 'football-training');
      expect(model?.leagues, hasLength(5));
      expect(
        model?.leagues.every(
          (league) =>
              league.homeWeights.length == FootballMobileEngine.featureCount,
        ),
        isTrue,
      );
      expect(await store.needsTraining(), isFalse);
      expect(await store.loadTrainingSnapshot(), isNull);

      final forecasts = FootballMobileEngine().predictLeagues(
        bundled: _bundledLeagues(dataset.leagues),
        dataset: dataset,
        model: model,
      );
      expect(forecasts.every((league) => league.forecasts.length == 1), isTrue);
      expect(
        forecasts.first.forecasts.single.totalDistribution.fold<double>(
          0,
          (sum, value) => sum + value,
        ),
        closeTo(1, 0.000001),
      );
    },
  );

  test('does not activate an old football training snapshot', () async {
    await store.saveDataset(_dataset(version: 'old'));
    final service = FootballTrainingService(store: store);
    await service.prepare();
    await store.saveDataset(_dataset(version: 'new', extraMatch: true));

    expect(await service.run(), isTrue);

    expect((await store.loadJob())?.stage, contains('已有新賽果'));
    expect(await store.loadModel(), isNull);
  });

  test('persists immutable timestamped football market snapshots', () async {
    final capturedAt = DateTime.utc(2026, 7, 13, 10);
    const matchId = 'E0:2026-07-14:Alpha:Beta';
    await store.saveOddsSnapshot(
      FootballOddsSnapshot(
        matchId: matchId,
        capturedAt: capturedAt,
        source: 'Betfair Historical Data Basic',
        marketId: '1.123',
        marketTime: DateTime.utc(2026, 7, 14, 19),
        line: 9.5,
        overOdds: 1.95,
        underOdds: 2.02,
      ),
    );
    await store.saveWeatherSnapshot(
      FootballWeatherSnapshot(
        matchId: matchId,
        capturedAt: capturedAt,
        validAt: DateTime.utc(2026, 7, 14, 19),
        source: 'Open-Meteo',
        latitude: 51.5,
        longitude: -0.1,
        temperatureC: 18,
        precipitationProbability: 25,
        windSpeedKmh: 12,
      ),
    );

    final odds = await store.loadOddsSnapshots();
    final weather = await store.loadWeatherSnapshots();

    expect(odds.single.marketOverProbability, closeTo(0.509, 0.001));
    expect(weather.single.temperatureC, 18);
    await expectLater(
      store.saveOddsSnapshot(
        FootballOddsSnapshot(
          matchId: matchId,
          capturedAt: capturedAt,
          source: 'Betfair Historical Data Basic',
          marketId: '1.123',
          marketTime: DateTime.utc(2026, 7, 14, 19),
          line: 9.5,
          overOdds: 1.9,
          underOdds: 2.02,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.saveOddsSnapshot(
        FootballOddsSnapshot(
          matchId: 'late',
          capturedAt: DateTime.utc(2026, 7, 14, 20),
          source: 'Betfair Historical Data Basic',
          marketId: '1.124',
          marketTime: DateTime.utc(2026, 7, 14, 19),
          line: 9.5,
          overOdds: 1.95,
          underOdds: 2.02,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.saveWeatherSnapshot(
        FootballWeatherSnapshot(
          matchId: 'late-weather',
          capturedAt: DateTime.utc(2026, 7, 14, 20),
          validAt: DateTime.utc(2026, 7, 14, 19),
          source: 'Open-Meteo',
          latitude: 51.5,
          longitude: -0.1,
          temperatureC: 18,
          precipitationProbability: 25,
          windSpeedKmh: 12,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

MobileFootballDataset _dataset({
  required String version,
  bool extraMatch = false,
}) {
  const configs = [
    FootballLeagueConfig(
      code: 'E0',
      name: '英超',
      supportCode: 'E1',
      supportName: '英冠',
    ),
    FootballLeagueConfig(
      code: 'SP1',
      name: '西甲',
      supportCode: 'SP2',
      supportName: '西乙',
    ),
    FootballLeagueConfig(
      code: 'F1',
      name: '法甲',
      supportCode: 'F2',
      supportName: '法乙',
    ),
    FootballLeagueConfig(
      code: 'D1',
      name: '德甲',
      supportCode: 'D2',
      supportName: '德乙',
    ),
    FootballLeagueConfig(
      code: 'I1',
      name: '意甲',
      supportCode: 'I2',
      supportName: '意乙',
    ),
  ];
  final rows = <FootballMatchRecord>[];
  for (final league in configs) {
    final count = extraMatch ? 121 : 120;
    for (var index = 0; index < count; index++) {
      final date = DateTime.utc(2024, 1, 1).add(Duration(days: index));
      final home = index % 8;
      final away = (index * 3 + 1) % 8;
      rows.add(
        FootballMatchRecord(
          division: league.code,
          date: date.toIso8601String().substring(0, 10),
          homeTeam: '${league.code}-T$home',
          awayTeam: '${league.code}-T$away',
          homeCorners: 3 + (index + home) % 6,
          awayCorners: 2 + (index + away) % 6,
          homeGoals: index % 4,
          awayGoals: (index + 1) % 3,
          homeShots: 9 + index % 10,
          awayShots: 8 + (index + 2) % 10,
          homeShotsOnTarget: 3 + index % 6,
          awayShotsOnTarget: 2 + (index + 1) % 6,
          homeOdds: 1.8 + home / 10,
          drawOdds: 3.2,
          awayOdds: 2.1 + away / 10,
          over25Odds: 1.9,
          under25Odds: 1.9,
        ),
      );
    }
  }
  rows.sort((left, right) => left.date.compareTo(right.date));
  return MobileFootballDataset(
    schemaVersion: 1,
    datasetVersion: version,
    generatedAt: DateTime.now().toIso8601String(),
    leagues: configs,
    rows: rows,
    fixtures: [
      for (final league in configs)
        FootballMatchRecord(
          division: league.code,
          date: '2025-05-10',
          homeTeam: '${league.code}-T0',
          awayTeam: '${league.code}-T1',
          homeOdds: 2,
          drawOdds: 3.2,
          awayOdds: 3.5,
          over25Odds: 1.9,
          under25Odds: 1.9,
        ),
    ],
  );
}

List<LeagueForecastData> _bundledLeagues(List<FootballLeagueConfig> configs) =>
    [
      for (final league in configs)
        LeagueForecastData(
          code: league.code,
          name: league.name,
          supportName: league.supportName,
          status: '測試',
          model: const ModelSummary(
            selectedCandidate: 'dynamic',
            selectedCandidateLabel: 'Dynamic',
            trainedThrough: '2024-12-31',
            firstSeason: '2024/25',
            lastSeason: '2024/25',
            trainingMatches: 100,
            supportMatches: 0,
            supportName: '次級聯賽',
            validationMatches: 10,
            holdoutMatches: 10,
            maeTotalCorners: 3,
            baselineMaeHoldout: 3,
            maeSkillVsDynamicPercent: 0,
            withinTwoHoldout: 0.5,
            brierOver9_5: 0.25,
            brierSkillOver9_5Percent: 0,
            calibrationErrorOver9_5: 0.05,
          ),
          forecasts: const [],
          recentBacktests: const [],
        ),
    ];
