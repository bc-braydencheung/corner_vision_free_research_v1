import 'dart:convert';
import 'dart:io';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Upgrading the app must not throw away the model an older build trained:
/// those files carry the 22 columns that existed before the shot-quality
/// proxy, and they are the only model on device until retraining finishes.
void main() {
  late Directory directory;
  late FootballStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('corner-legacy-model-');
    store = FootballStore(directory: directory);
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test('a model file written by the previous build still loads', () async {
    final legacy = _model(FootballMobileEngine.minimumFeatureCount).toJson();
    // The older build never wrote this key at all.
    for (final league in legacy['leagues']! as List<Object?>) {
      (league! as Map<String, Object?>).remove('selectedFeatures');
    }
    await File(
      '${directory.path}/active-model.json',
    ).writeAsString(jsonEncode(legacy));

    final loaded = await store.loadModel();

    expect(loaded, isNotNull);
    expect(loaded!.version, 'released-before-proxy');
    expect(
      loaded.leagues.every(
        (league) =>
            league.featureMeans.length ==
            FootballMobileEngine.minimumFeatureCount,
      ),
      isTrue,
    );
    // No selectedFeatures key existed back then: absent means all columns.
    expect(loaded.leagues.first.selectedFeatures, isEmpty);
  });

  test(
    'activation accepts both the old and the current column count',
    () async {
      await store.saveCandidateAndActivate(
        _model(FootballMobileEngine.minimumFeatureCount),
      );
      expect(
        (await store.loadModel())!.leagues.first.featureMeans,
        hasLength(FootballMobileEngine.minimumFeatureCount),
      );

      await store.saveCandidateAndActivate(
        _model(FootballMobileEngine.featureCount, version: 'current'),
      );
      expect(
        (await store.loadModel())!.leagues.first.featureMeans,
        hasLength(FootballMobileEngine.featureCount),
      );
    },
  );

  test('a truncated column count is still rejected', () async {
    await expectLater(
      store.saveCandidateAndActivate(
        FootballMobileEngine.minimumFeatureCount > 1
            ? _model(FootballMobileEngine.minimumFeatureCount - 1)
            : _model(0),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

MobileFootballModel _model(
  int columns, {
  String version = 'released-before-proxy',
}) => MobileFootballModel(
  version: version,
  datasetVersion: 'legacy-dataset',
  trainedThrough: const {
    'E0': '2025-12-31',
    'SP1': '2025-12-31',
    'D1': '2025-12-31',
    'I1': '2025-12-31',
    'F1': '2025-12-31',
  },
  leagues: [
    for (final code in const ['E0', 'SP1', 'D1', 'I1', 'F1'])
      MobileFootballLeagueModel(
        code: code,
        featureMeans: List<double>.filled(columns, 0),
        featureScales: List<double>.filled(columns, 1),
        homeWeights: List<double>.filled(columns, 0),
        homeIntercept: 1.7,
        awayWeights: List<double>.filled(columns, 0),
        awayIntercept: 1.6,
        totalWeights: List<double>.filled(columns, 0),
        totalIntercept: 2.3,
        trainingMatches: 300,
        holdoutMatches: 60,
        mae: 2.6,
        baselineMae: 2.7,
        brierOver95: 0.24,
        baselineBrierOver95: 0.25,
        dispersion: 8,
        useModel: true,
      ),
  ],
);
