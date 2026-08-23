import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../models/feature_ablation.dart';
import '../models/football_mobile.dart';
import 'football_mobile_engine.dart';
import 'football_store.dart';
import 'hkjc_training_bridge.dart';
import 'shadow_service.dart';
import 'walk_forward.dart';

const footballTrainingTask = 'ai.devin.corner.EdgeWise.footballTraining';
const footballTrainingUniqueName = footballTrainingTask;

class FootballTrainingCoordinator {
  static Future<FootballTrainingJob> start({bool restart = false}) async {
    final store = FootballStore();
    final service = FootballTrainingService(store: store);
    final job = await service.prepare(restart: restart);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await Workmanager().registerOneOffTask(
        footballTrainingUniqueName,
        footballTrainingTask,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
    final directory = await store.storageDirectory();
    final path = directory.path;
    unawaited(
      Isolate.run(
        () => FootballTrainingService(
          store: FootballStore(directory: Directory(path)),
        ).run(),
      ),
    );
    return job;
  }

  static Future<void> pause() async {
    final store = FootballStore();
    final job = await store.loadJob();
    if (job == null || !job.isUnfinished) return;
    await store.saveJob(
      FootballTrainingJob(
        id: job.id,
        datasetVersion: job.datasetVersion,
        status: 'paused',
        stage: '已暫停 · ${job.stage}',
        progress: job.progress,
        epoch: job.epoch,
        updatedAt: DateTime.now(),
        checkpoint: job.checkpoint,
      ),
    );
  }

  static Future<void> resume() async {
    final store = FootballStore();
    final job = await store.loadJob();
    if (job == null || !job.isPaused) return;
    await store.saveJob(
      FootballTrainingJob(
        id: job.id,
        datasetVersion: job.datasetVersion,
        status: 'queued',
        stage: '準備從暫停恢復',
        progress: job.progress,
        epoch: job.epoch,
        updatedAt: DateTime.now(),
        checkpoint: job.checkpoint,
      ),
    );
    await FootballTrainingCoordinator.start();
  }
}

class FootballTrainingService {
  FootballTrainingService({
    FootballStore? store,
    FootballMobileEngine? engine,
    ShadowService? shadowService,
  }) : store = store ?? FootballStore(),
       engine = engine ?? FootballMobileEngine(),
       _shadowService = shadowService ?? ShadowService();

  static const _epochs = 30;
  static const _foldEpochs = 12;
  static const _learningRate = 0.025;
  static const _l2 = 0.003;
  final FootballStore store;
  final FootballMobileEngine engine;
  final ShadowService _shadowService;

  /// [dataset] plus the settled HKJC corner counts of the same matches.
  ///
  /// The free history publishes a finished round days later, so without this
  /// the model trains on rounds the app already knows the corner counts of. A
  /// failure here leaves the free history alone rather than blocking training.
  Future<MobileFootballDataset> _withHkjcResults(
    MobileFootballDataset dataset,
  ) async {
    try {
      return withHkjcTrainingRows(
        dataset: dataset,
        forecasts: await _shadowService.load(),
        results: await store.loadHkjcCornerResults(),
        asOf: DateTime.now(),
      );
    } on Object {
      return dataset;
    }
  }

  Future<FootballTrainingJob> prepare({bool restart = false}) async {
    final previous = await store.loadJob();
    final snapshot = await store.loadTrainingSnapshot();
    if (!restart &&
        previous != null &&
        snapshot != null &&
        previous.datasetVersion == snapshot.datasetVersion &&
        (previous.isUnfinished || previous.status == 'failed')) {
      final resumed = FootballTrainingJob(
        id: previous.id,
        datasetVersion: previous.datasetVersion,
        status: 'queued',
        stage: '準備從安全 checkpoint 繼續五大聯賽訓練',
        progress: previous.progress,
        epoch: previous.epoch,
        updatedAt: DateTime.now(),
        checkpoint: previous.checkpoint,
      );
      await store.saveJob(resumed);
      return resumed;
    }
    final dataset = await _withHkjcResults(await store.loadDataset());
    await store.saveTrainingSnapshot(dataset);
    final now = DateTime.now();
    final job = FootballTrainingJob(
      id: now.microsecondsSinceEpoch.toString(),
      datasetVersion: dataset.datasetVersion,
      status: 'queued',
      stage: '準備五大聯賽日期式資料切分',
      progress: 0,
      epoch: 0,
      updatedAt: now,
      checkpoint: const {
        'leagueIndex': 0,
        'stageIndex': 0,
        'completedModels': <Object?>[],
      },
    );
    await store.saveJob(job);
    return job;
  }

  Future<bool> run() async {
    if (!await store.acquireTrainingLock()) {
      return false;
    }
    try {
      final loadedJob = await store.loadJob();
      if (loadedJob == null || !loadedJob.isUnfinished) {
        return true;
      }
      var job = loadedJob;
      final dataset = await store.loadTrainingSnapshot();
      if (dataset == null || dataset.datasetVersion != job.datasetVersion) {
        await _fail(job, '找不到相符的足球訓練資料快照，請以最新資料重新開始');
        return true;
      }
      var checkpoint = Map<String, Object?>.from(job.checkpoint);
      var leagueIndex = (checkpoint['leagueIndex'] as num? ?? 0).toInt();
      final completedModels =
          (checkpoint['completedModels'] as List<Object?>? ?? const [])
              .map(
                (item) => MobileFootballLeagueModel.fromJson(
                  (item as Map).cast<String, Object?>(),
                ),
              )
              .toList();
      // A stored attribution sweep of this very dataset saves one walk-forward
      // per feature; anything measured on other data is ignored.
      final storedAblation = await store.loadFeatureAblation();
      final measuredAblation =
          storedAblation != null &&
              storedAblation.datasetVersion == dataset.datasetVersion
          ? storedAblation.leagues
          : const <FeatureAblationLeague>[];
      while (leagueIndex < dataset.leagues.length) {
        final league = dataset.leagues[leagueIndex];
        final allRows = engine.buildTrainingRows(dataset, league);
        if (allRows.length < 100) {
          await _fail(job, '${league.name}可用訓練場次不足');
          return true;
        }
        final split = _split(allRows);
        // Feature selection is a model decision, so it is measured on the
        // development window only and then frozen for every stage.
        final selectionKey = 'selectedFeatures:${league.code}';
        var keptFeatures = const <int>[];
        if (checkpoint[selectionKey] case final List<Object?> stored) {
          keptFeatures = stored
              .map((value) => (value as num).toInt())
              .toList(growable: false);
        } else {
          FeatureAblationLeague? measured;
          for (final entry in measuredAblation) {
            if (entry.code == league.code) {
              measured = entry;
            }
          }
          final selection = selectFeatures(
            rows: split.development,
            measured: measured,
          );
          keptFeatures = selection.adopted ? selection.kept : const [];
        }
        checkpoint = {...checkpoint, selectionKey: keptFeatures};
        final droppedFeatures = <int>{
          if (keptFeatures.isNotEmpty)
            for (
              var index = 0;
              index < FootballMobileEngine.featureCount;
              index++
            )
              if (!keptFeatures.contains(index)) index,
        };
        var stageIndex = (checkpoint['stageIndex'] as num? ?? 0).toInt();
        while (stageIndex < 3) {
          final rows = switch (stageIndex) {
            0 => split.development,
            1 => split.preHoldout,
            _ => allRows,
          };
          final stageLabel = switch (stageIndex) {
            0 => '${league.name} Development 訓練及 validation 選模',
            1 => '${league.name} Pre-holdout 訓練及最後閘門',
            _ => '${league.name} 全量資料訓練候選模型',
          };
          final startEpoch = (checkpoint['epoch'] as num? ?? 0).toInt();
          final normalisation = _mask(
            startEpoch == 0
                ? _normalisation(rows)
                : _Normalisation(
                    _values(checkpoint['featureMeans']),
                    _values(checkpoint['featureScales']),
                  ),
            droppedFeatures,
          );
          var homeWeights = _weights(checkpoint['homeWeights']);
          var awayWeights = _weights(checkpoint['awayWeights']);
          var totalWeights = _weights(checkpoint['totalWeights']);
          var homeIntercept =
              (checkpoint['homeIntercept'] as num?)?.toDouble() ??
              _initialIntercept(rows, (row) => row.homeCorners);
          var awayIntercept =
              (checkpoint['awayIntercept'] as num?)?.toDouble() ??
              _initialIntercept(rows, (row) => row.awayCorners);
          var totalIntercept =
              (checkpoint['totalIntercept'] as num?)?.toDouble() ??
              _initialIntercept(rows, (row) => row.totalCorners);
          for (var epoch = startEpoch; epoch < _epochs; epoch++) {
            // Check for pause request
            final currentJob = await store.loadJob();
            if (currentJob?.isPaused ?? false) {
              await store.releaseTrainingLock();
              return true;
            }
            (homeWeights, homeIntercept) = _trainEpoch(
              rows,
              normalisation,
              homeWeights,
              homeIntercept,
              (row) => row.homeCorners,
            );
            (awayWeights, awayIntercept) = _trainEpoch(
              rows,
              normalisation,
              awayWeights,
              awayIntercept,
              (row) => row.awayCorners,
            );
            (totalWeights, totalIntercept) = _trainEpoch(
              rows,
              normalisation,
              totalWeights,
              totalIntercept,
              (row) => row.totalCorners,
            );
            if ((epoch + 1) % 5 == 0 || epoch == _epochs - 1) {
              final unit = leagueIndex * 3 + stageIndex;
              final progress =
                  (unit + (epoch + 1) / _epochs) /
                  (dataset.leagues.length * 3) *
                  96;
              checkpoint = {
                ...checkpoint,
                'leagueIndex': leagueIndex,
                'stageIndex': stageIndex,
                'epoch': epoch + 1,
                'featureMeans': normalisation.means,
                'featureScales': normalisation.scales,
                'homeWeights': homeWeights,
                'homeIntercept': homeIntercept,
                'awayWeights': awayWeights,
                'awayIntercept': awayIntercept,
                'totalWeights': totalWeights,
                'totalIntercept': totalIntercept,
                'completedModels': completedModels
                    .map((model) => model.toJson())
                    .toList(),
              };
              job = FootballTrainingJob(
                id: job.id,
                datasetVersion: job.datasetVersion,
                status: 'training',
                stage: stageLabel,
                progress: progress,
                epoch: epoch + 1,
                updatedAt: DateTime.now(),
                checkpoint: checkpoint,
              );
              await store.saveJob(job);
              await store.touchTrainingLock();
            }
          }
          if (stageIndex == 0) {
            final validation = _evaluate(
              split.validation,
              normalisation,
              homeWeights,
              homeIntercept,
              awayWeights,
              awayIntercept,
              totalWeights,
              totalIntercept,
            );
            checkpoint = {
              ...checkpoint,
              'validationSelected':
                  validation.mae < validation.baselineMae &&
                  validation.brierOver95 <= validation.baselineBrierOver95,
            };
          } else if (stageIndex == 1) {
            final holdout = _evaluate(
              split.holdout,
              normalisation,
              homeWeights,
              homeIntercept,
              awayWeights,
              awayIntercept,
              totalWeights,
              totalIntercept,
            );
            final walkForward = _walkForward(allRows);
            checkpoint = {
              ...checkpoint,
              'walkForward': walkForward.toJson(),
              'holdoutMae': holdout.mae,
              'holdoutBaselineMae': holdout.baselineMae,
              'holdoutBrierOver95': holdout.brierOver95,
              'holdoutBaselineBrierOver95': holdout.baselineBrierOver95,
              'holdoutDispersion': holdout.dispersion,
            };
          } else {
            final walkForward = checkpoint['walkForward'] == null
                ? WalkForwardReport.empty
                : WalkForwardReport.fromJson(
                    (checkpoint['walkForward'] as Map).cast<String, Object?>(),
                  );
            // A model is released only if it also survived the purged
            // walk-forward folds; when the history is too short to run them the
            // single hold-out gate still applies on its own.
            final useModel =
                checkpoint['validationSelected'] == true &&
                (checkpoint['holdoutMae'] as num).toDouble() <
                    (checkpoint['holdoutBaselineMae'] as num).toDouble() &&
                (checkpoint['holdoutBrierOver95'] as num).toDouble() <=
                    (checkpoint['holdoutBaselineBrierOver95'] as num)
                        .toDouble() &&
                (walkForward.foldCount < 3 || walkForward.gatePassed);
            completedModels.add(
              MobileFootballLeagueModel(
                code: league.code,
                featureMeans: normalisation.means,
                featureScales: normalisation.scales,
                homeWeights: homeWeights,
                homeIntercept: homeIntercept,
                awayWeights: awayWeights,
                awayIntercept: awayIntercept,
                totalWeights: totalWeights,
                totalIntercept: totalIntercept,
                useModel: useModel,
                trainingMatches: allRows.length,
                holdoutMatches: split.holdout.length,
                mae: useModel
                    ? (checkpoint['holdoutMae'] as num).toDouble()
                    : (checkpoint['holdoutBaselineMae'] as num).toDouble(),
                baselineMae: (checkpoint['holdoutBaselineMae'] as num)
                    .toDouble(),
                brierOver95: useModel
                    ? (checkpoint['holdoutBrierOver95'] as num).toDouble()
                    : (checkpoint['holdoutBaselineBrierOver95'] as num)
                          .toDouble(),
                baselineBrierOver95:
                    (checkpoint['holdoutBaselineBrierOver95'] as num)
                        .toDouble(),
                dispersion: (checkpoint['holdoutDispersion'] as num).toDouble(),
                selectedFeatures: keptFeatures,
                walkForward: walkForward.foldCount == 0 ? null : walkForward,
              ),
            );
          }
          stageIndex++;
          checkpoint = {
            ...checkpoint,
            'leagueIndex': leagueIndex,
            'stageIndex': stageIndex,
            'epoch': 0,
            'completedModels': completedModels
                .map((model) => model.toJson())
                .toList(),
            'homeWeights': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'awayWeights': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'totalWeights': List<double>.filled(
              FootballMobileEngine.featureCount,
              0,
            ),
            'homeIntercept': null,
            'awayIntercept': null,
            'totalIntercept': null,
          };
          await store.saveJob(
            FootballTrainingJob(
              id: job.id,
              datasetVersion: job.datasetVersion,
              status: 'training',
              stage: '已保存 ${league.name} 安全 checkpoint',
              progress:
                  (leagueIndex * 3 + stageIndex) /
                  (dataset.leagues.length * 3) *
                  96,
              epoch: 0,
              updatedAt: DateTime.now(),
              checkpoint: checkpoint,
            ),
          );
          await store.touchTrainingLock();
        }
        leagueIndex++;
        checkpoint = {
          'leagueIndex': leagueIndex,
          'stageIndex': 0,
          'epoch': 0,
          'completedModels': completedModels
              .map((model) => model.toJson())
              .toList(),
        };
        await store.saveJob(
          FootballTrainingJob(
            id: job.id,
            datasetVersion: job.datasetVersion,
            status: 'training',
            stage: '${league.name}已完成，準備下一個聯賽',
            progress: leagueIndex / dataset.leagues.length * 96,
            epoch: 0,
            updatedAt: DateTime.now(),
            checkpoint: checkpoint,
          ),
        );
        await store.touchTrainingLock();
      }
      final activeDataset = await store.loadDataset();
      if (activeDataset.datasetVersion != job.datasetVersion) {
        await store.saveJob(
          FootballTrainingJob(
            id: job.id,
            datasetVersion: job.datasetVersion,
            status: 'completed',
            stage: '舊足球資料快照已完成；已有新賽果，因此沒有啟用',
            progress: 100,
            epoch: _epochs,
            updatedAt: DateTime.now(),
          ),
        );
        await store.deleteTrainingSnapshot();
        return true;
      }
      final model = MobileFootballModel(
        version: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
        datasetVersion: dataset.datasetVersion,
        trainedThrough: {
          for (final league in dataset.leagues)
            league.code: dataset.trainedThrough(league.code),
        },
        leagues: completedModels,
      );
      await store.saveCandidateAndActivate(model);
      final upgraded = completedModels.where((model) => model.useModel).length;
      await store.saveJob(
        FootballTrainingJob(
          id: job.id,
          datasetVersion: job.datasetVersion,
          status: 'completed',
          stage: upgraded > 0
              ? '驗證完成，$upgraded 個聯賽候選模型已原子啟用'
              : '訓練完成但未升級，五大聯賽保留動態基準',
          progress: 100,
          epoch: _epochs,
          updatedAt: DateTime.now(),
        ),
      );
      await store.clearTrainingNeeded();
      await store.deleteTrainingSnapshot();
      return true;
    } on Object catch (error) {
      final job = await store.loadJob();
      if (job != null) {
        await _fail(job, '$error');
      }
      return false;
    } finally {
      await store.releaseTrainingLock();
    }
  }

  (List<double>, double) _trainEpoch(
    List<FootballTrainingRow> rows,
    _Normalisation normalisation,
    List<double> initialWeights,
    double initialIntercept,
    int Function(FootballTrainingRow) target,
  ) {
    final weights = initialWeights.isEmpty
        ? List<double>.filled(FootballMobileEngine.featureCount, 0)
        : List<double>.from(initialWeights);
    final gradient = List<double>.filled(weights.length, 0);
    var interceptGradient = 0.0;
    for (final row in rows) {
      final features = _normalise(row.features, normalisation);
      final expectedLog = _dot(weights, features) + initialIntercept;
      final actualLog = log(target(row) + 0.5);
      final error = (expectedLog - actualLog).clamp(-4.0, 4.0);
      interceptGradient += error;
      for (var index = 0; index < weights.length; index++) {
        gradient[index] += error * features[index];
      }
    }
    final scale = 1 / max(rows.length, 1);
    for (var index = 0; index < weights.length; index++) {
      weights[index] -=
          _learningRate * (gradient[index] * scale + _l2 * weights[index]);
    }
    return (
      weights,
      initialIntercept - _learningRate * interceptGradient * scale,
    );
  }

  _FootballEvaluation _evaluate(
    List<FootballTrainingRow> rows,
    _Normalisation normalisation,
    List<double> homeWeights,
    double homeIntercept,
    List<double> awayWeights,
    double awayIntercept,
    List<double> totalWeights,
    double totalIntercept,
  ) {
    var absoluteError = 0.0;
    var baselineAbsoluteError = 0.0;
    var squaredError = 0.0;
    var brier = 0.0;
    var baselineBrier = 0.0;
    var meanPrediction = 0.0;
    for (final row in rows) {
      final features = _normalise(row.features, normalisation);
      var home = _predict(homeWeights, homeIntercept, features);
      var away = _predict(awayWeights, awayIntercept, features);
      final total = _predict(totalWeights, totalIntercept, features);
      final scale = total / max(home + away, 0.1);
      home *= scale;
      away *= scale;
      final prediction = home + away;
      final actual = row.totalCorners.toDouble();
      absoluteError += (prediction - actual).abs();
      baselineAbsoluteError += (row.baselineTotal - actual).abs();
      squaredError += pow(prediction - actual, 2);
      meanPrediction += prediction;
      final actualOver = actual > 9.5 ? 1.0 : 0.0;
      brier += pow(
        FootballMobileEngine.over95Probability(prediction) - actualOver,
        2,
      );
      baselineBrier += pow(
        FootballMobileEngine.over95Probability(row.baselineTotal) - actualOver,
        2,
      );
    }
    final count = max(rows.length, 1);
    final average = meanPrediction / count;
    final dispersion = max(
      (squaredError / count - average) / max(average * average, 0.1),
      0.02,
    );
    return _FootballEvaluation(
      mae: absoluteError / count,
      baselineMae: baselineAbsoluteError / count,
      brierOver95: brier / count,
      baselineBrierOver95: baselineBrier / count,
      dispersion: dispersion,
    );
  }

  /// Purged, embargoed walk-forward validation of the league's history.
  ///
  /// Every fold is retrained from scratch on its own training rows with a
  /// shorter schedule than the release run, which is enough to tell a real edge
  /// from one lucky window without making an on-device retrain unaffordable.
  WalkForwardReport _walkForward(
    List<FootballTrainingRow> rows, {
    Set<int> dropped = const {},
    int folds = 4,
  }) {
    return runPurgedWalkForward<FootballTrainingRow>(
      rows: rows,
      folds: folds,
      dateOf: (row) => DateTime.parse(row.date),
      evaluate: (train, test) {
        if (train.length < 80 || test.isEmpty) {
          return null;
        }
        final normalisation = _mask(_normalisation(train), dropped);
        var homeWeights = <double>[];
        var awayWeights = <double>[];
        var totalWeights = <double>[];
        var homeIntercept = _initialIntercept(train, (row) => row.homeCorners);
        var awayIntercept = _initialIntercept(train, (row) => row.awayCorners);
        var totalIntercept = _initialIntercept(
          train,
          (row) => row.totalCorners,
        );
        for (var epoch = 0; epoch < _foldEpochs; epoch++) {
          (homeWeights, homeIntercept) = _trainEpoch(
            train,
            normalisation,
            homeWeights,
            homeIntercept,
            (row) => row.homeCorners,
          );
          (awayWeights, awayIntercept) = _trainEpoch(
            train,
            normalisation,
            awayWeights,
            awayIntercept,
            (row) => row.awayCorners,
          );
          (totalWeights, totalIntercept) = _trainEpoch(
            train,
            normalisation,
            totalWeights,
            totalIntercept,
            (row) => row.totalCorners,
          );
        }
        final scored = _evaluate(
          test,
          normalisation,
          homeWeights,
          homeIntercept,
          awayWeights,
          awayIntercept,
          totalWeights,
          totalIntercept,
        );
        return WalkForwardFoldMetrics(
          mae: scored.mae,
          baselineMae: scored.baselineMae,
          brier: scored.brierOver95,
          baselineBrier: scored.baselineBrierOver95,
          samples: test.length,
        );
      },
    );
  }

  /// Drops every feature in turn inside the purged folds and scores the folds
  /// again, so a feature's value is measured out of sample instead of assumed.
  ///
  /// [folds] is lower than the release run: the whole sweep costs one
  /// walk-forward per feature, and the ranking is what matters here, not a
  /// release decision.
  FeatureAblationLeague? ablationOf({
    required String code,
    required String name,
    required List<FootballTrainingRow> rows,
    int folds = 3,
  }) {
    final full = _walkForward(rows, folds: folds);
    if (full.foldCount < 2) {
      return null;
    }
    final entries = <FeatureAblationEntry>[];
    for (var index = 0; index < FootballMobileEngine.featureCount; index++) {
      final without = _walkForward(rows, dropped: {index}, folds: folds);
      if (without.foldCount != full.foldCount) {
        continue;
      }
      entries.add(
        FeatureAblationEntry(
          index: index,
          name: index < footballFeatureNames.length
              ? footballFeatureNames[index]
              : '特徵 $index',
          maeDelta: without.mae - full.mae,
          brierDelta: without.brier - full.brier,
          folds: without.foldCount,
        ),
      );
    }
    return FeatureAblationLeague(
      code: code,
      name: name,
      baseMae: full.mae,
      baseBrier: full.brier,
      folds: full.foldCount,
      samples: full.samples,
      entries: entries,
    );
  }

  /// Cuts the feature set down to the few columns the purged folds pay for.
  ///
  /// Twenty-two flat features on a few thousand matches overfits, so the folds
  /// pick the survivors: features are ranked by what dropping them costs out of
  /// sample, the best [maxKept] with a positive cost are re-scored together, and
  /// the reduced set is adopted only if it matches or beats the full set. When
  /// no feature shows out-of-sample value the model keeps everything and says
  /// so, because an arbitrary cut is not an improvement.
  ///
  /// [rows] must exclude the validation and hold-out windows: this is a model
  /// decision and may not see the data that later judges it.
  ///
  /// [measured] reuses an attribution sweep that was already computed on the
  /// same rows, which is the difference between two extra folds and one per
  /// feature; it is only trusted when its own fold count says it ran.
  FeatureSelection selectFeatures({
    required List<FootballTrainingRow> rows,
    FeatureAblationLeague? measured,
    int maxKept = 5,
    int folds = 3,
  }) {
    final full = _walkForward(rows, folds: folds);
    if (full.foldCount < 2) {
      return const FeatureSelection.all(note: '折數不足，未篩特徵');
    }
    final scored = <(int, double)>[];
    if (measured != null && measured.folds >= 2) {
      for (final entry in measured.entries) {
        scored.add((entry.index, entry.maeDelta));
      }
    } else {
      for (var index = 0; index < FootballMobileEngine.featureCount; index++) {
        final without = _walkForward(rows, dropped: {index}, folds: folds);
        if (without.foldCount != full.foldCount) {
          continue;
        }
        scored.add((index, without.mae - full.mae));
      }
    }
    final ranked = scored.where((entry) => entry.$2 > 0).toList()
      ..sort((left, right) => right.$2.compareTo(left.$2));
    if (ranked.isEmpty) {
      return FeatureSelection.all(
        note: '折外無特徵顯示訊號，保留全部特徵',
        folds: full.foldCount,
      );
    }
    final kept = ranked
        .take(maxKept)
        .map((entry) => entry.$1)
        .toList(growable: false);
    final reduced = _walkForward(
      rows,
      dropped: {
        for (var index = 0; index < FootballMobileEngine.featureCount; index++)
          if (!kept.contains(index)) index,
      },
      folds: folds,
    );
    final adopted =
        reduced.foldCount == full.foldCount && reduced.mae <= full.mae;
    return FeatureSelection(
      kept: kept,
      baseMae: full.mae,
      keptMae: reduced.mae,
      adopted: adopted,
      folds: full.foldCount,
      note: adopted ? '' : '精簡特徵集折外未勝全特徵，保留全部特徵',
    );
  }

  _FootballSplit _split(List<FootballTrainingRow> rows) {
    final validationStart = max((rows.length * 0.7).floor(), 1);
    final holdoutStart = max((rows.length * 0.85).floor(), validationStart + 1);
    return _FootballSplit(
      development: rows.take(validationStart).toList(),
      validation: rows
          .skip(validationStart)
          .take(holdoutStart - validationStart)
          .toList(),
      preHoldout: rows.take(holdoutStart).toList(),
      holdout: rows.skip(holdoutStart).toList(),
    );
  }

  _Normalisation _normalisation(List<FootballTrainingRow> rows) {
    final means = List<double>.filled(FootballMobileEngine.featureCount, 0);
    for (final row in rows) {
      for (var index = 0; index < means.length; index++) {
        means[index] += row.features[index];
      }
    }
    for (var index = 0; index < means.length; index++) {
      means[index] /= max(rows.length, 1);
    }
    final scales = List<double>.filled(means.length, 0);
    for (final row in rows) {
      for (var index = 0; index < scales.length; index++) {
        scales[index] += pow(row.features[index] - means[index], 2);
      }
    }
    for (var index = 0; index < scales.length; index++) {
      scales[index] = sqrt(scales[index] / max(rows.length, 1));
      if (scales[index] < 0.0001) {
        scales[index] = 1;
      }
    }
    return _Normalisation(means, scales);
  }

  /// Freezes the dropped columns at their training mean.
  ///
  /// A normalised feature that is always zero cannot move a prediction, which
  /// is what "without this feature" has to mean inside a fold: the fold is
  /// retrained from scratch, so no leftover weight survives.
  static _Normalisation _mask(_Normalisation source, Set<int> dropped) =>
      dropped.isEmpty
      ? source
      : _Normalisation(source.means, source.scales, dropped: dropped);

  static List<double> _normalise(
    List<double> features,
    _Normalisation normalisation,
  ) => [
    for (var index = 0; index < features.length; index++)
      if (normalisation.dropped.contains(index))
        0.0
      else
        (features[index] - normalisation.means[index]) /
            normalisation.scales[index],
  ];

  static double _initialIntercept(
    List<FootballTrainingRow> rows,
    int Function(FootballTrainingRow) target,
  ) {
    final mean =
        rows.fold(0.0, (sum, row) => sum + target(row)) / max(rows.length, 1);
    return log(mean + 0.5);
  }

  static double _predict(
    List<double> weights,
    double intercept,
    List<double> features,
  ) => (exp((_dot(weights, features) + intercept).clamp(-2.0, 3.5)) - 0.5)
      .clamp(0.1, 20);

  static double _dot(List<double> weights, List<double> features) {
    var output = 0.0;
    for (var index = 0; index < weights.length; index++) {
      output += weights[index] * features[index];
    }
    return output;
  }

  static List<double> _weights(Object? value) => value == null
      ? List<double>.filled(FootballMobileEngine.featureCount, 0)
      : _values(value);

  static List<double> _values(Object? value) => (value as List<Object?>)
      .map((item) => (item as num).toDouble())
      .toList(growable: false);

  Future<void> _fail(FootballTrainingJob job, String error) {
    return store.saveJob(
      FootballTrainingJob(
        id: job.id,
        datasetVersion: job.datasetVersion,
        status: 'failed',
        stage: '足球訓練已暫停，舊模型繼續使用',
        progress: job.progress,
        epoch: job.epoch,
        updatedAt: DateTime.now(),
        error: error,
        checkpoint: job.checkpoint,
      ),
    );
  }
}

class _Normalisation {
  const _Normalisation(this.means, this.scales, {this.dropped = const {}});

  final List<double> means;
  final List<double> scales;

  /// Columns frozen at zero, i.e. features this model may not read.
  final Set<int> dropped;
}

class _FootballSplit {
  const _FootballSplit({
    required this.development,
    required this.validation,
    required this.preHoldout,
    required this.holdout,
  });

  final List<FootballTrainingRow> development;
  final List<FootballTrainingRow> validation;
  final List<FootballTrainingRow> preHoldout;
  final List<FootballTrainingRow> holdout;
}

class _FootballEvaluation {
  const _FootballEvaluation({
    required this.mae,
    required this.baselineMae,
    required this.brierOver95,
    required this.baselineBrierOver95,
    required this.dispersion,
  });

  final double mae;
  final double baselineMae;
  final double brierOver95;
  final double baselineBrierOver95;
  final double dispersion;
}
