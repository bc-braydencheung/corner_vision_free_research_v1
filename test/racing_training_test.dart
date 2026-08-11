import 'dart:convert';
import 'dart:io';

import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/racing_store.dart';
import 'package:edgewise/services/racing_training_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late RacingStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('corner-racing-test-');
    store = RacingStore(directory: directory);
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  test(
    'restores the previous active dataset when the new file is corrupt',
    () async {
      final first = _dataset(raceCount: 24, version: 'first');
      final second = _dataset(raceCount: 25, version: 'second');
      await store.saveDataset(first);
      await store.saveDataset(second);
      await File('${directory.path}/active-dataset.json').writeAsString('{');

      final restored = await store.loadDataset();

      expect(restored.datasetVersion, 'first');
      expect(restored.rows, hasLength(96));
    },
  );

  test(
    'resumes a checkpoint and activates only a validated mobile model',
    () async {
      final dataset = _dataset(raceCount: 40, version: 'training');
      await store.saveDataset(dataset);
      final service = RacingTrainingService(store: store);
      final prepared = await service.prepare();
      await store.saveJob(
        RacingTrainingJob(
          id: prepared.id,
          datasetVersion: prepared.datasetVersion,
          status: 'training',
          stage: 'checkpoint',
          progress: 2.5,
          epoch: 5,
          updatedAt: DateTime.now(),
          checkpoint: {
            'stageIndex': 0,
            'epoch': 5,
            'winWeights': List<double>.filled(17, 0),
            'winIntercept': -2.2,
            'placeWeights': List<double>.filled(17, 0),
            'placeIntercept': -0.9,
          },
        ),
      );

      expect(await service.run(), isTrue);
      final job = await store.loadJob();
      final model = await store.loadModel();

      expect(job?.status, 'completed');
      expect(job?.progress, 100);
      expect(model?.datasetVersion, 'training');
      expect(model?.winWeights, hasLength(17));
      expect(await store.loadTrainingSnapshot(), isNull);
    },
  );

  test(
    'finishes an immutable old snapshot without replacing a newer model',
    () async {
      await store.saveDataset(_dataset(raceCount: 32, version: 'old'));
      final service = RacingTrainingService(store: store);
      await service.prepare();
      await store.saveDataset(_dataset(raceCount: 33, version: 'new'));

      expect(await service.run(), isTrue);
      final job = await store.loadJob();

      expect(job?.status, 'completed');
      expect(job?.stage, contains('已有新賽果'));
      expect(await store.loadModel(), isNull);
    },
  );

  test('persists immutable timestamped full-race odds snapshots', () async {
    final capturedAt = DateTime.utc(2026, 7, 15, 10, 20);
    await store.saveOddsSnapshot(
      RacingOddsSnapshot(
        raceId: 'HK:2026-07-15:HV:1',
        capturedAt: capturedAt,
        raceTime: DateTime.utc(2026, 7, 15, 11),
        source: 'hkjc-personal-research',
        oddsByHorse: const {'H1': 3.2, 'H2': 5.8},
      ),
    );

    final snapshots = await store.loadOddsSnapshots();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.capturedAt, capturedAt);
    expect(snapshots.single.oddsByHorse['H1'], 3.2);
    expect(snapshots.single.isFinal, isFalse);
    await expectLater(
      store.saveOddsSnapshot(
        RacingOddsSnapshot(
          raceId: 'HK:2026-07-15:HV:1',
          capturedAt: capturedAt,
          raceTime: DateTime.utc(2026, 7, 15, 11),
          source: 'hkjc-personal-research',
          oddsByHorse: const {'H1': 3.3, 'H2': 5.8},
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.saveOddsSnapshot(
        RacingOddsSnapshot(
          raceId: 'late',
          capturedAt: DateTime.utc(2026, 7, 15, 12),
          raceTime: DateTime.utc(2026, 7, 15, 11),
          source: 'hkjc-personal-research',
          oddsByHorse: const {'H1': 3.2, 'H2': 5.8},
        ),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

MobileRacingDataset _dataset({
  required int raceCount,
  required String version,
}) {
  final rows = <RacingTrainingRow>[];
  for (var race = 0; race < raceCount; race++) {
    for (var runner = 0; runner < 4; runner++) {
      rows.add(
        RacingTrainingRow(
          raceId: 'R$race',
          date: '2026-01-${(race % 28 + 1).toString().padLeft(2, '0')}',
          fieldSize: 4,
          won: runner == race % 4 ? 1 : 0,
          placed: runner == race % 4 || runner == (race + 1) % 4 ? 1 : 0,
          features: [
            0.5,
            runner / 4,
            1.2,
            race.isEven ? 1 : 0,
            0,
            4,
            2,
            runner == race % 4 ? 0.2 : 0.05,
            runner < 2 ? 0.5 : 0.25,
            0.5,
            0.1,
            3,
            0.1,
            0.3,
            0.1,
            0.3,
            runner == race % 4 ? 0.8 : 0.4,
          ],
        ),
      );
    }
  }
  return MobileRacingDataset(
    schemaVersion: 1,
    datasetVersion: version,
    trainedThrough: '2026-02-28',
    featureNames: List.generate(17, (index) => 'f$index'),
    rows: rows,
    horses: const {},
    jockeys: const {},
    trainers: const {},
    horseNames: const {},
    results: [
      jsonDecode('{"raceId":"R0","horseId":"H0","finishPosition":1}')
          as Map<String, Object?>,
    ],
  );
}
