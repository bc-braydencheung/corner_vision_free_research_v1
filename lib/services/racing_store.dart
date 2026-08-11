import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/racing_mobile.dart';

class RacingStore {
  RacingStore({Directory? directory}) : _directoryOverride = directory;

  static const _seedAsset = 'assets/data/racing_mobile_seed.json.gz';
  final Directory? _directoryOverride;

  Future<Directory> storageDirectory() => _directory();

  Future<Directory> _directory() async {
    final override = _directoryOverride;
    if (override != null) {
      if (!override.existsSync()) {
        await override.create(recursive: true);
      }
      return override;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/edgewise_racing');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<File> _file(String name) async {
    final directory = await _directory();
    return File('${directory.path}/$name');
  }

  Future<void> initialize() async {
    final active = await _file('active-dataset.json');
    if (active.existsSync()) {
      return;
    }
    final bytes = await rootBundle.load(_seedAsset);
    final decoded = gzip.decode(bytes.buffer.asUint8List());
    final seed = utf8.decode(decoded);
    MobileRacingDataset.fromJson(
      (jsonDecode(seed) as Map).cast<String, Object?>(),
    );
    await _writeAtomic(active, seed);
  }

  Future<MobileRacingDataset> loadDataset() async {
    await initialize();
    return MobileRacingDataset.fromJson(
      (await _readMap('active-dataset.json'))!,
    );
  }

  Future<void> saveDataset(MobileRacingDataset dataset) async {
    if (dataset.schemaVersion != 1 ||
        dataset.rows.isEmpty ||
        dataset.featureNames.length != 17 ||
        dataset.rows.any(
          (row) =>
              row.raceId.isEmpty ||
              row.features.length != dataset.featureNames.length,
        )) {
      throw const FormatException('Invalid mobile racing dataset.');
    }
    final encoded = jsonEncode(dataset.toJson());
    MobileRacingDataset.fromJson(
      (jsonDecode(encoded) as Map).cast<String, Object?>(),
    );
    await _writeAtomic(await _file('active-dataset.json'), encoded);
  }

  Future<Map<String, Object?>?> loadUpcoming() =>
      _readMap('active-upcoming.json');

  Future<void> saveUpcoming(Map<String, Object?> value) =>
      _writeAtomicMap('active-upcoming.json', value);

  Future<List<RacingOddsSnapshot>> loadOddsSnapshots() async {
    final value = await _readMap('odds-snapshots.json');
    return (value?['snapshots'] as List<Object?>? ?? const [])
        .map(
          (snapshot) => RacingOddsSnapshot.fromJson(
            (snapshot as Map).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<void> saveOddsSnapshot(RacingOddsSnapshot snapshot) async {
    _validateOddsSnapshot(snapshot);
    final snapshots = await loadOddsSnapshots();
    for (final current in snapshots) {
      if (current.raceId == snapshot.raceId &&
          current.capturedAt.toUtc() == snapshot.capturedAt.toUtc() &&
          current.source == snapshot.source) {
        if (current.isFinal == snapshot.isFinal &&
            current.raceTime?.toUtc() == snapshot.raceTime?.toUtc() &&
            mapEquals(current.oddsByHorse, snapshot.oddsByHorse)) {
          return;
        }
        throw const FormatException('Racing odds snapshots are immutable.');
      }
    }
    snapshots.add(snapshot);
    snapshots.sort(
      (left, right) => left.capturedAt.compareTo(right.capturedAt),
    );
    if (snapshots.length > 5000) {
      snapshots.removeRange(0, snapshots.length - 5000);
    }
    await _writeAtomicMap('odds-snapshots.json', {
      'schemaVersion': 1,
      'snapshots': snapshots.map((value) => value.toJson()).toList(),
    });
  }

  Future<Map<String, Object?>> exportResearchSnapshots() async {
    final odds = await loadOddsSnapshots();
    return {
      'schemaVersion': 1,
      'oddsSnapshots': odds.map((snapshot) => snapshot.toJson()).toList(),
    };
  }

  Future<int> importResearchSnapshots(Map<String, Object?> payload) async {
    validateResearchSnapshots(payload);
    final existing = await loadOddsSnapshots();
    final merged = {
      for (final snapshot in existing) _oddsIdentity(snapshot): snapshot,
    };
    var imported = 0;
    for (final value
        in payload['oddsSnapshots'] as List<Object?>? ?? const []) {
      final snapshot = RacingOddsSnapshot.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      final key = _oddsIdentity(snapshot);
      final current = merged[key];
      if (current != null) {
        if (!_sameOddsSnapshot(current, snapshot)) {
          throw const FormatException('Racing odds snapshots are immutable.');
        }
      } else {
        merged[key] = snapshot;
        imported++;
      }
    }
    final snapshots = merged.values.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    if (snapshots.length > 5000) {
      snapshots.removeRange(0, snapshots.length - 5000);
    }
    await _writeAtomicMap('odds-snapshots.json', {
      'schemaVersion': 1,
      'snapshots': snapshots.map((value) => value.toJson()).toList(),
    });
    return imported;
  }

  void validateResearchSnapshots(Map<String, Object?> payload) {
    if ((payload['schemaVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('Unsupported racing snapshot backup.');
    }
    final imported = <String, RacingOddsSnapshot>{};
    for (final value
        in payload['oddsSnapshots'] as List<Object?>? ?? const []) {
      final snapshot = RacingOddsSnapshot.fromJson(
        (value as Map).cast<String, Object?>(),
      );
      _validateOddsSnapshot(snapshot);
      final key = _oddsIdentity(snapshot);
      final current = imported[key];
      if (current != null && !_sameOddsSnapshot(current, snapshot)) {
        throw const FormatException('Racing odds snapshots are immutable.');
      }
      imported[key] = snapshot;
    }
  }

  static String _oddsIdentity(RacingOddsSnapshot snapshot) =>
      '${snapshot.raceId}:${snapshot.capturedAt.toUtc().toIso8601String()}:'
      '${snapshot.source}';

  static bool _sameOddsSnapshot(
    RacingOddsSnapshot left,
    RacingOddsSnapshot right,
  ) =>
      left.source == right.source &&
      left.isFinal == right.isFinal &&
      left.raceTime?.toUtc() == right.raceTime?.toUtc() &&
      mapEquals(left.oddsByHorse, right.oddsByHorse);

  static void _validateOddsSnapshot(RacingOddsSnapshot snapshot) {
    if (snapshot.raceId.isEmpty ||
        snapshot.source.isEmpty ||
        snapshot.oddsByHorse.length < 2 ||
        snapshot.oddsByHorse.values.any(
          (odds) => !odds.isFinite || odds <= 1 || odds > 1000,
        ) ||
        (!snapshot.isFinal &&
            (snapshot.raceTime == null ||
                !snapshot.capturedAt.toUtc().isBefore(
                  snapshot.raceTime!.toUtc(),
                )))) {
      throw const FormatException('Invalid racing odds snapshot.');
    }
  }

  Future<Map<String, Object?>> exportRecoveryState() async {
    final model = await loadModel();
    final job = await loadJob();
    return {
      'schemaVersion': 1,
      'activeModel': model?.toJson(),
      'trainingJob': job?.toJson(),
    };
  }

  Future<(bool, bool)> importRecoveryState(Map<String, Object?> payload) async {
    if ((payload['schemaVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('Unsupported racing recovery backup.');
    }
    var modelRestored = false;
    var checkpointRestored = false;
    final modelPayload = payload['activeModel'] as Map?;
    if (modelPayload != null) {
      await saveCandidateAndActivate(
        MobileRacingModel.fromJson(modelPayload.cast<String, Object?>()),
      );
      modelRestored = true;
    }
    final jobPayload = payload['trainingJob'] as Map?;
    if (jobPayload != null) {
      final job = RacingTrainingJob.fromJson(
        jobPayload.cast<String, Object?>(),
      );
      final snapshot = await loadTrainingSnapshot();
      if (snapshot != null && snapshot.datasetVersion == job.datasetVersion) {
        await saveJob(job);
        checkpointRestored = true;
      }
    }
    return (modelRestored, checkpointRestored);
  }

  Future<void> saveTrainingSnapshot(MobileRacingDataset dataset) =>
      _writeAtomicMap('training-dataset.json', dataset.toJson());

  Future<MobileRacingDataset?> loadTrainingSnapshot() async {
    final value = await _readMap('training-dataset.json');
    return value == null ? null : MobileRacingDataset.fromJson(value);
  }

  Future<void> deleteTrainingSnapshot() async {
    final file = await _file('training-dataset.json');
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<MobileRacingModel?> loadModel() async {
    final value = await _readMap('active-model.json');
    return value == null ? null : MobileRacingModel.fromJson(value);
  }

  Future<void> saveCandidateAndActivate(MobileRacingModel model) async {
    if (model.winWeights.length != 17 ||
        model.placeWeights.length != 17 ||
        model.datasetVersion.isEmpty ||
        model.winWeights.any((value) => !value.isFinite) ||
        model.placeWeights.any((value) => !value.isFinite)) {
      throw const FormatException('Invalid mobile racing model.');
    }
    final candidate = await _file('candidate-model.json');
    final encoded = jsonEncode(model.toJson());
    final verified = MobileRacingModel.fromJson(
      (jsonDecode(encoded) as Map).cast<String, Object?>(),
    );
    await _writeAtomic(candidate, encoded);
    final active = await _file('active-model.json');
    try {
      await _writeAtomic(active, encoded);
      final activated = MobileRacingModel.fromJson(
        (jsonDecode(await active.readAsString()) as Map)
            .cast<String, Object?>(),
      );
      if (activated.version != verified.version ||
          activated.datasetVersion != verified.datasetVersion) {
        throw const FormatException('Activated model self-check failed.');
      }
    } on Object {
      final backup = File('${active.path}.backup');
      if (backup.existsSync()) {
        if (active.existsSync()) {
          await active.delete();
        }
        await backup.copy(active.path);
      }
      rethrow;
    }
    if (candidate.existsSync()) {
      await candidate.delete();
    }
  }

  Future<RacingTrainingJob?> loadJob() async {
    final value = await _readMap('training-job.json');
    return value == null ? null : RacingTrainingJob.fromJson(value);
  }

  Future<void> saveJob(RacingTrainingJob job) =>
      _writeAtomicMap('training-job.json', job.toJson());

  Future<void> touchTrainingLock() async {
    final lock = await _file('training.lock');
    if (lock.existsSync()) {
      await lock.setLastModified(DateTime.now());
    }
  }

  Future<void> deleteJob() async {
    final file = await _file('training-job.json');
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<bool> acquireTrainingLock() async {
    final lock = await _file('training.lock');
    if (lock.existsSync()) {
      final age = DateTime.now().difference(lock.lastModifiedSync());
      if (age < const Duration(seconds: 30)) {
        return false;
      }
      await lock.delete();
    }
    try {
      await lock.create(exclusive: true);
      await lock.writeAsString(DateTime.now().toIso8601String(), flush: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> releaseTrainingLock() async {
    final lock = await _file('training.lock');
    if (lock.existsSync()) {
      await lock.delete();
    }
  }

  Future<Map<String, Object?>?> _readMap(String name) async {
    final file = await _file(name);
    if (!file.existsSync()) {
      return null;
    }
    try {
      return (jsonDecode(await file.readAsString()) as Map)
          .cast<String, Object?>();
    } on Object {
      final backup = File('${file.path}.backup');
      if (!backup.existsSync()) {
        rethrow;
      }
      final value = (jsonDecode(await backup.readAsString()) as Map)
          .cast<String, Object?>();
      await file.delete();
      await backup.copy(file.path);
      return value;
    }
  }

  Future<void> _writeAtomicMap(String name, Map<String, Object?> value) =>
      _writeAtomicFile(name, jsonEncode(value));

  Future<void> _writeAtomicFile(String name, String contents) async {
    await _writeAtomic(await _file(name), contents);
  }

  Future<void> _writeAtomic(File active, String contents) async {
    final staging = File('${active.path}.staging');
    final backup = File('${active.path}.backup');
    await staging.writeAsString(contents, flush: true);
    if (backup.existsSync()) {
      await backup.delete();
    }
    if (active.existsSync()) {
      await active.rename(backup.path);
    }
    try {
      await staging.rename(active.path);
    } on Object {
      if (!active.existsSync() && backup.existsSync()) {
        await backup.rename(active.path);
      }
      rethrow;
    }
  }
}
