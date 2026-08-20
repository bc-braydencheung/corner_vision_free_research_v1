import 'dart:io';

import 'package:edgewise/models/feature_ablation.dart';
import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/feature_ablation_service.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:edgewise/services/football_training_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late FootballStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('corner-ablation-test-');
    store = FootballStore(directory: directory);
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('names every training feature exactly once', () {
    expect(footballFeatureNames, hasLength(FootballMobileEngine.featureCount));
    expect(
      footballFeatureNames.toSet(),
      hasLength(footballFeatureNames.length),
    );
  });

  test('scores every feature inside the purged folds', () {
    final dataset = _dataset();
    final engine = FootballMobileEngine();
    final service = FootballTrainingService(store: store, engine: engine);
    final rows = engine.buildTrainingRows(dataset, dataset.leagues.first);

    final league = service.ablationOf(
      code: 'E0',
      name: '英超',
      rows: rows,
      folds: 3,
    );

    expect(league, isNotNull);
    expect(league!.folds, greaterThanOrEqualTo(2));
    expect(league.entries, hasLength(FootballMobileEngine.featureCount));
    expect(
      league.entries.map((entry) => entry.name),
      containsAll(footballFeatureNames),
    );
    // Dropping a column has to change the folds, otherwise the mask is a no-op
    // and the whole attribution would be meaningless.
    expect(
      league.entries.any((entry) => entry.maeDelta.abs() > 0.000001),
      isTrue,
    );
    expect(league.baseMae, greaterThan(0));
  });

  test('classifies signal and noise by the measured deltas', () {
    const carrying = FeatureAblationEntry(
      index: 0,
      name: '主隊角球基準',
      maeDelta: 0.04,
      brierDelta: 0.002,
      folds: 3,
    );
    const noise = FeatureAblationEntry(
      index: 1,
      name: '客隊角球基準',
      maeDelta: -0.03,
      brierDelta: -0.004,
      folds: 3,
    );
    const flat = FeatureAblationEntry(
      index: 2,
      name: '聯賽主隊平均',
      maeDelta: 0.001,
      brierDelta: 0,
      folds: 3,
    );

    expect(carrying.carriesSignal, isTrue);
    expect(carrying.hurts, isFalse);
    expect(noise.carriesSignal, isFalse);
    expect(noise.hurts, isTrue);
    expect(flat.carriesSignal, isFalse);
    expect(flat.hurts, isFalse);

    final league = FeatureAblationLeague(
      code: 'E0',
      name: '英超',
      baseMae: 2.8,
      baseBrier: 0.24,
      folds: 3,
      samples: 300,
      entries: const [carrying, noise, flat],
    );
    expect(league.useful.single.name, '主隊角球基準');
    expect(league.harmful.single.name, '客隊角球基準');
  });

  test('keeps at most five features and only when the folds agree', () {
    final dataset = _dataset();
    final engine = FootballMobileEngine();
    final service = FootballTrainingService(store: store, engine: engine);
    final rows = engine.buildTrainingRows(dataset, dataset.leagues.first);

    final selection = service.selectFeatures(rows: rows, folds: 3);

    expect(selection.kept.length, lessThanOrEqualTo(5));
    expect(selection.kept.toSet(), hasLength(selection.kept.length));
    if (selection.adopted) {
      expect(selection.kept, isNotEmpty);
      // A cut is only adopted when it is no worse out of sample.
      expect(selection.keptMae, lessThanOrEqualTo(selection.baseMae));
      expect(
        selection.droppedOf(FootballMobileEngine.featureCount),
        hasLength(FootballMobileEngine.featureCount - selection.kept.length),
      );
    } else {
      // Rejecting the cut has to leave every feature in play, with a reason.
      expect(selection.note, isNotEmpty);
      expect(selection.droppedOf(FootballMobileEngine.featureCount), isEmpty);
    }
  });

  test('reuses a measured sweep to rank the features', () {
    final dataset = _dataset();
    final engine = FootballMobileEngine();
    final service = FootballTrainingService(store: store, engine: engine);
    final rows = engine.buildTrainingRows(dataset, dataset.leagues.first);
    final measured = FeatureAblationLeague(
      code: 'E0',
      name: '英超',
      baseMae: 2.8,
      baseBrier: 0.24,
      folds: 3,
      samples: rows.length,
      entries: [
        for (var index = 0; index < FootballMobileEngine.featureCount; index++)
          FeatureAblationEntry(
            index: index,
            name: footballFeatureNames[index],
            // Only the first three columns are worth anything here.
            maeDelta: index < 3 ? 0.3 - index * 0.01 : -0.2,
            brierDelta: index < 3 ? 0.01 : -0.01,
            folds: 3,
          ),
      ],
    );

    final selection = service.selectFeatures(
      rows: rows,
      measured: measured,
      folds: 3,
    );

    expect(selection.kept, [0, 1, 2]);
  });

  test('keeps every feature when nothing scored out of sample', () {
    final dataset = _dataset();
    final engine = FootballMobileEngine();
    final service = FootballTrainingService(store: store, engine: engine);
    final rows = engine.buildTrainingRows(dataset, dataset.leagues.first);
    final worthless = FeatureAblationLeague(
      code: 'E0',
      name: '英超',
      baseMae: 2.8,
      baseBrier: 0.24,
      folds: 3,
      samples: rows.length,
      entries: [
        for (var index = 0; index < FootballMobileEngine.featureCount; index++)
          FeatureAblationEntry(
            index: index,
            name: footballFeatureNames[index],
            maeDelta: -0.1,
            brierDelta: -0.01,
            folds: 3,
          ),
      ],
    );

    final selection = service.selectFeatures(
      rows: rows,
      measured: worthless,
      folds: 3,
    );

    expect(selection.adopted, isFalse);
    expect(selection.kept, isEmpty);
    expect(selection.note, contains('保留全部特徵'));
  });

  test('too few folds refuses to select rather than guessing', () {
    final engine = FootballMobileEngine();
    final service = FootballTrainingService(store: store, engine: engine);

    final selection = service.selectFeatures(rows: const [], folds: 3);

    expect(selection.adopted, isFalse);
    expect(selection.folds, 0);
    expect(selection.note, contains('折數不足'));
  });

  test(
    'stores the report with the dataset version it was measured on',
    () async {
      final report = FeatureAblationReport(
        computedAt: DateTime.utc(2026, 8, 17, 4),
        datasetVersion: 'ablation-test',
        leagues: const [
          FeatureAblationLeague(
            code: 'E0',
            name: '英超',
            baseMae: 2.8,
            baseBrier: 0.24,
            folds: 3,
            samples: 300,
            entries: [
              FeatureAblationEntry(
                index: 0,
                name: '主隊角球基準',
                maeDelta: 0.04,
                brierDelta: 0.002,
                folds: 3,
              ),
            ],
          ),
        ],
        note: '樣本不足未評估：西甲',
      );

      await store.saveFeatureAblation(report);
      final restored = await FeatureAblationService(store: store).load();

      expect(restored, isNotNull);
      expect(restored!.datasetVersion, 'ablation-test');
      expect(restored.computedAt, DateTime.utc(2026, 8, 17, 4));
      expect(restored.note, contains('西甲'));
      expect(
        restored.leagues.single.entries.single.maeDelta,
        closeTo(0.04, 1e-9),
      );
      expect(restored.isEmpty, isFalse);
    },
  );
}

MobileFootballDataset _dataset() {
  const configs = [
    FootballLeagueConfig(
      code: 'E0',
      name: '英超',
      supportCode: 'E1',
      supportName: '英冠',
    ),
  ];
  final rows = <FootballMatchRecord>[];
  for (var index = 0; index < 420; index++) {
    final date = DateTime.utc(2023, 1, 1).add(Duration(days: index));
    final home = index % 10;
    final away = (index * 3 + 1) % 10;
    rows.add(
      FootballMatchRecord(
        division: 'E0',
        date: date.toIso8601String().substring(0, 10),
        homeTeam: 'T$home',
        awayTeam: 'T$away',
        homeCorners: 3 + (index + home) % 7,
        awayCorners: 2 + (index + away) % 6,
        homeGoals: index % 4,
        awayGoals: (index + 1) % 3,
        homeShots: 9 + index % 11,
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
  return MobileFootballDataset(
    schemaVersion: 1,
    datasetVersion: 'ablation-test',
    generatedAt: DateTime.now().toIso8601String(),
    leagues: configs,
    rows: rows,
    fixtures: const [],
  );
}
