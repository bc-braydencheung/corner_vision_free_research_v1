import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../models/racing_mobile.dart';
import 'football_training_service.dart';
import 'racing_mobile_engine.dart';
import 'racing_store.dart';

const racingTrainingTask = 'ai.devin.corner.EdgeWise.racingTraining';
const racingTrainingUniqueName = racingTrainingTask;

@pragma('vm:entry-point')
void racingBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == racingTrainingTask) {
      return RacingTrainingService().run();
    }
    if (task == footballTrainingTask) {
      return FootballTrainingService().run();
    }
    return true;
  });
}

class RacingTrainingCoordinator {
  static bool get _supportsBackgroundWork =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (_supportsBackgroundWork) {
      await Workmanager().initialize(racingBackgroundDispatcher);
    }
  }

  static Future<RacingTrainingJob> start({bool restart = false}) async {
    final store = RacingStore();
    final service = RacingTrainingService(store: store);
    final job = await service.prepare(restart: restart);
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await Workmanager().registerOneOffTask(
        racingTrainingUniqueName,
        racingTrainingTask,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    }
    final directory = await store.storageDirectory();
    final directoryPath = directory.path;
    unawaited(
      Isolate.run(
        () => RacingTrainingService(
          store: RacingStore(directory: Directory(directoryPath)),
        ).run(),
      ),
    );
    return job;
  }

  static Future<void> pause() async {
    final store = RacingStore();
    final job = await store.loadJob();
    if (job == null || !job.isUnfinished) return;
    await store.saveJob(
      RacingTrainingJob(
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
    final store = RacingStore();
    final job = await store.loadJob();
    if (job == null || !job.isPaused) return;
    await store.saveJob(
      RacingTrainingJob(
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
    await RacingTrainingCoordinator.start();
  }
}

class RacingTrainingService {
  RacingTrainingService({RacingStore? store}) : store = store ?? RacingStore();

  static const _epochs = 60;
  static const _learningRate = 0.045;
  static const _l2 = 0.004;
  final RacingStore store;

  Future<RacingTrainingJob> prepare({bool restart = false}) async {
    final previous = await store.loadJob();
    final snapshot = await store.loadTrainingSnapshot();
    if (!restart &&
        previous != null &&
        snapshot != null &&
        previous.datasetVersion == snapshot.datasetVersion &&
        (previous.isUnfinished || previous.status == 'failed')) {
      final resumed = RacingTrainingJob(
        id: previous.id,
        datasetVersion: previous.datasetVersion,
        status: 'queued',
        stage: '準備從安全 checkpoint 繼續',
        progress: previous.progress,
        epoch: previous.epoch,
        updatedAt: DateTime.now(),
        checkpoint: previous.checkpoint,
      );
      await store.saveJob(resumed);
      return resumed;
    }
    final dataset = await store.loadDataset();
    await store.saveTrainingSnapshot(dataset);
    final now = DateTime.now();
    final job = RacingTrainingJob(
      id: '${now.microsecondsSinceEpoch}',
      datasetVersion: dataset.datasetVersion,
      status: 'queued',
      stage: '準備日期式資料切分',
      progress: 0,
      epoch: 0,
      updatedAt: now,
      checkpoint: const {'stageIndex': 0},
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
      if (dataset == null) {
        await _fail(job, '找不到訓練資料快照，請以最新資料重新開始');
        return true;
      }
      if (job.datasetVersion != dataset.datasetVersion) {
        await _fail(job, '訓練資料快照版本不符，請以最新資料重新開始');
        return true;
      }
      final split = _split(dataset.rows);
      var checkpoint = Map<String, Object?>.from(job.checkpoint);
      var stageIndex = (checkpoint['stageIndex'] as num? ?? 0).toInt();
      while (stageIndex < 3) {
        final rows = switch (stageIndex) {
          0 => split.development,
          1 => split.preHoldout,
          _ => dataset.rows,
        };
        final stageLabel = switch (stageIndex) {
          0 => 'Development 訓練及 validation 選模',
          1 => 'Pre-holdout 訓練及最後閘門',
          _ => '全量資料訓練候選模型',
        };
        final startEpoch = (checkpoint['epoch'] as num? ?? 0).toInt();
        var winWeights = _weights(checkpoint['winWeights']);
        var placeWeights = _weights(checkpoint['placeWeights']);
        var winIntercept = (checkpoint['winIntercept'] as num? ?? -2.2)
            .toDouble();
        var placeIntercept = (checkpoint['placeIntercept'] as num? ?? -0.9)
            .toDouble();
        for (var epoch = startEpoch; epoch < _epochs; epoch++) {
          // Check for pause request
          final currentJob = await store.loadJob();
          if (currentJob?.isPaused ?? false) {
            await store.releaseTrainingLock();
            return true;
          }
          (winWeights, winIntercept) = _trainEpoch(
            rows,
            winWeights,
            winIntercept,
            (row) => row.won,
          );
          (placeWeights, placeIntercept) = _trainEpoch(
            rows,
            placeWeights,
            placeIntercept,
            (row) => row.placed,
          );
          if ((epoch + 1) % 5 == 0 || epoch == _epochs - 1) {
            final stageStart = stageIndex * 32.0;
            final progress = min(96.0, stageStart + (epoch + 1) / _epochs * 30);
            checkpoint = {
              ...checkpoint,
              'stageIndex': stageIndex,
              'epoch': epoch + 1,
              'winWeights': winWeights,
              'winIntercept': winIntercept,
              'placeWeights': placeWeights,
              'placeIntercept': placeIntercept,
            };
            job = RacingTrainingJob(
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
            winWeights,
            winIntercept,
            placeWeights,
            placeIntercept,
          );
          checkpoint = {
            ...checkpoint,
            'validationWinSelected':
                validation.winLogLoss < validation.baselineWinLogLoss,
            'validationPlaceSelected':
                validation.placeBrier < validation.baselinePlaceBrier,
          };
        } else if (stageIndex == 1) {
          final holdout = _evaluate(
            split.holdout,
            winWeights,
            winIntercept,
            placeWeights,
            placeIntercept,
          );
          checkpoint = {
            ...checkpoint,
            'holdoutWinWeights': winWeights,
            'holdoutWinIntercept': winIntercept,
            'holdoutPlaceWeights': placeWeights,
            'holdoutPlaceIntercept': placeIntercept,
            'holdoutWinLogLoss': holdout.winLogLoss,
            'holdoutBaselineWinLogLoss': holdout.baselineWinLogLoss,
            'holdoutWinBrier': holdout.winBrier,
            'holdoutPlaceBrier': holdout.placeBrier,
            'holdoutBaselinePlaceBrier': holdout.baselinePlaceBrier,
          };
        } else {
          final activeDataset = await store.loadDataset();
          if (activeDataset.datasetVersion != job.datasetVersion) {
            await store.saveJob(
              RacingTrainingJob(
                id: job.id,
                datasetVersion: job.datasetVersion,
                status: 'completed',
                stage: '舊資料快照已完成；已有新賽果，因此沒有啟用',
                progress: 100,
                epoch: _epochs,
                updatedAt: DateTime.now(),
                checkpoint: const {},
              ),
            );
            await store.deleteTrainingSnapshot();
            return true;
          }
          final useWinModel =
              checkpoint['validationWinSelected'] == true &&
              (checkpoint['holdoutWinLogLoss'] as num).toDouble() <
                  (checkpoint['holdoutBaselineWinLogLoss'] as num).toDouble();
          final usePlaceModel =
              checkpoint['validationPlaceSelected'] == true &&
              (checkpoint['holdoutPlaceBrier'] as num).toDouble() <
                  (checkpoint['holdoutBaselinePlaceBrier'] as num).toDouble();
          final model = MobileRacingModel(
            version: 'mobile-${DateTime.now().millisecondsSinceEpoch}',
            datasetVersion: dataset.datasetVersion,
            trainedThrough: dataset.trainedThrough,
            winWeights: winWeights,
            winIntercept: winIntercept,
            placeWeights: placeWeights,
            placeIntercept: placeIntercept,
            useWinModel: useWinModel,
            usePlaceModel: usePlaceModel,
            trainingRaces: dataset.rows.map((row) => row.raceId).toSet().length,
            holdoutRaces: split.holdout.map((row) => row.raceId).toSet().length,
            winLogLoss: useWinModel
                ? (checkpoint['holdoutWinLogLoss'] as num).toDouble()
                : (checkpoint['holdoutBaselineWinLogLoss'] as num).toDouble(),
            baselineWinLogLoss: (checkpoint['holdoutBaselineWinLogLoss'] as num)
                .toDouble(),
            winBrier: (checkpoint['holdoutWinBrier'] as num).toDouble(),
            placeBrier: usePlaceModel
                ? (checkpoint['holdoutPlaceBrier'] as num).toDouble()
                : (checkpoint['holdoutBaselinePlaceBrier'] as num).toDouble(),
            baselinePlaceBrier: (checkpoint['holdoutBaselinePlaceBrier'] as num)
                .toDouble(),
          );
          await store.saveCandidateAndActivate(model);
          await store.saveJob(
            RacingTrainingJob(
              id: job.id,
              datasetVersion: job.datasetVersion,
              status: 'completed',
              stage: useWinModel || usePlaceModel
                  ? '驗證完成，候選模型已原子啟用'
                  : '訓練完成但未升級，保留動態基準',
              progress: 100,
              epoch: _epochs,
              updatedAt: DateTime.now(),
              checkpoint: const {},
            ),
          );
          await store.deleteTrainingSnapshot();
          return true;
        }
        stageIndex++;
        checkpoint = {
          ...checkpoint,
          'stageIndex': stageIndex,
          'epoch': 0,
          'winWeights': List<double>.filled(RacingMobileEngine.featureCount, 0),
          'winIntercept': -2.2,
          'placeWeights': List<double>.filled(
            RacingMobileEngine.featureCount,
            0,
          ),
          'placeIntercept': -0.9,
        };
        await store.saveJob(
          RacingTrainingJob(
            id: job.id,
            datasetVersion: job.datasetVersion,
            status: 'training',
            stage: '已保存安全 checkpoint',
            progress: min(stageIndex * 32, 96).toDouble(),
            epoch: 0,
            updatedAt: DateTime.now(),
            checkpoint: checkpoint,
          ),
        );
        await store.touchTrainingLock();
      }
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
    List<RacingTrainingRow> rows,
    List<double> initialWeights,
    double initialIntercept,
    int Function(RacingTrainingRow) target,
  ) {
    final weights = initialWeights.isEmpty
        ? List<double>.filled(RacingMobileEngine.featureCount, 0)
        : List<double>.from(initialWeights);
    final gradient = List<double>.filled(weights.length, 0);
    var interceptGradient = 0.0;
    for (final row in rows) {
      final probability = _sigmoid(
        _dot(weights, row.features) + initialIntercept,
      );
      final error = probability - target(row);
      interceptGradient += error;
      for (var index = 0; index < weights.length; index++) {
        gradient[index] += error * row.features[index];
      }
    }
    final scale = 1 / max(rows.length, 1);
    for (var index = 0; index < weights.length; index++) {
      weights[index] -=
          _learningRate * (gradient[index] * scale + _l2 * weights[index]);
    }
    final intercept =
        initialIntercept - _learningRate * interceptGradient * scale;
    return (weights, intercept);
  }

  _Evaluation _evaluate(
    List<RacingTrainingRow> rows,
    List<double> winWeights,
    double winIntercept,
    List<double> placeWeights,
    double placeIntercept,
  ) {
    final byRace = <String, List<RacingTrainingRow>>{};
    for (final row in rows) {
      byRace.putIfAbsent(row.raceId, () => []).add(row);
    }
    var winLoss = 0.0;
    var baselineLoss = 0.0;
    var winBrier = 0.0;
    var placeBrier = 0.0;
    var baselinePlaceBrier = 0.0;
    var winnerCount = 0;
    var runnerCount = 0;
    for (final race in byRace.values) {
      final rawWin = race
          .map((row) => _sigmoid(_dot(winWeights, row.features) + winIntercept))
          .toList();
      final baselineWin = race
          .map((row) => exp(_baselineScore(row.features)))
          .toList();
      final rawPlace = race
          .map(
            (row) =>
                _sigmoid(_dot(placeWeights, row.features) + placeIntercept),
          )
          .toList();
      final slots = race.first.fieldSize >= 7
          ? 3.0
          : race.first.fieldSize >= 4
          ? 2.0
          : 0.0;
      final win = RacingMobileEngine.normalise(rawWin, 1);
      final baseline = RacingMobileEngine.normalise(baselineWin, 1);
      final place = RacingMobileEngine.normalise(rawPlace, slots);
      final baselinePlace = RacingMobileEngine.normalise(
        race.map((row) => row.features[8]).toList(),
        slots,
      );
      for (var index = 0; index < race.length; index++) {
        final row = race[index];
        if (row.won == 1) {
          winLoss -= log(max(win[index], 0.00000001));
          baselineLoss -= log(max(baseline[index], 0.00000001));
          winnerCount++;
        }
        winBrier += pow(win[index] - row.won, 2);
        placeBrier += pow(place[index] - row.placed, 2);
        baselinePlaceBrier += pow(baselinePlace[index] - row.placed, 2);
        runnerCount++;
      }
    }
    return _Evaluation(
      winLogLoss: winLoss / max(winnerCount, 1),
      baselineWinLogLoss: baselineLoss / max(winnerCount, 1),
      winBrier: winBrier / max(runnerCount, 1),
      placeBrier: placeBrier / max(runnerCount, 1),
      baselinePlaceBrier: baselinePlaceBrier / max(runnerCount, 1),
    );
  }

  _Split _split(List<RacingTrainingRow> rows) {
    final raceIds = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      if (seen.add(row.raceId)) {
        raceIds.add(row.raceId);
      }
    }
    final validationStart = max((raceIds.length * 0.7).floor(), 1);
    final holdoutStart = max(
      (raceIds.length * 0.85).floor(),
      validationStart + 1,
    );
    final developmentIds = raceIds.take(validationStart).toSet();
    final validationIds = raceIds
        .skip(validationStart)
        .take(holdoutStart - validationStart)
        .toSet();
    final holdoutIds = raceIds.skip(holdoutStart).toSet();
    return _Split(
      development: rows
          .where((row) => developmentIds.contains(row.raceId))
          .toList(),
      validation: rows
          .where((row) => validationIds.contains(row.raceId))
          .toList(),
      preHoldout: rows
          .where((row) => !holdoutIds.contains(row.raceId))
          .toList(),
      holdout: rows.where((row) => holdoutIds.contains(row.raceId)).toList(),
    );
  }

  Future<void> _fail(RacingTrainingJob job, String error) {
    return store.saveJob(
      RacingTrainingJob(
        id: job.id,
        datasetVersion: job.datasetVersion,
        status: 'failed',
        stage: '訓練已暫停，舊模型繼續使用',
        progress: job.progress,
        epoch: job.epoch,
        updatedAt: DateTime.now(),
        error: error,
        checkpoint: job.checkpoint,
      ),
    );
  }

  static List<double> _weights(Object? value) => value == null
      ? List<double>.filled(RacingMobileEngine.featureCount, 0)
      : (value as List<Object?>)
            .map((item) => (item as num).toDouble())
            .toList();

  static double _sigmoid(double value) =>
      1 / (1 + exp(-value.clamp(-30.0, 30.0)));

  static double _dot(List<double> weights, List<double> features) {
    var total = 0.0;
    for (var index = 0; index < weights.length; index++) {
      total += weights[index] * features[index];
    }
    return total;
  }

  static double _baselineScore(List<double> row) =>
      1.6 * row[7] +
      0.8 * row[9] +
      0.55 * row[12] +
      0.55 * row[14] +
      0.35 * row[16] -
      0.12 * row[0];
}

class _Split {
  const _Split({
    required this.development,
    required this.validation,
    required this.preHoldout,
    required this.holdout,
  });

  final List<RacingTrainingRow> development;
  final List<RacingTrainingRow> validation;
  final List<RacingTrainingRow> preHoldout;
  final List<RacingTrainingRow> holdout;
}

class _Evaluation {
  const _Evaluation({
    required this.winLogLoss,
    required this.baselineWinLogLoss,
    required this.winBrier,
    required this.placeBrier,
    required this.baselinePlaceBrier,
  });

  final double winLogLoss;
  final double baselineWinLogLoss;
  final double winBrier;
  final double placeBrier;
  final double baselinePlaceBrier;
}
