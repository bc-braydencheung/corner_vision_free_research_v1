import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/feature_ablation.dart';
import '../models/football_mobile.dart';

class FootballStore {
  FootballStore({Directory? directory}) : _directoryOverride = directory;

  static const _seedAsset = 'assets/data/football_mobile_seed.json.gz';

  /// Highest dataset schema this build can read and write.
  static const supportedSchemaVersion = 2;
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
    final directory = Directory('${support.path}/edgewise_football');
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
    final active = await _file('active-dataset.json.gz');
    if (active.existsSync()) {
      return;
    }
    try {
      final bytes = (await rootBundle.load(_seedAsset)).buffer.asUint8List();
      MobileFootballDataset.fromJson(
        (jsonDecode(utf8.decode(gzip.decode(bytes))) as Map)
            .cast<String, Object?>(),
      );
      await _writeAtomicBytes(active, bytes);
    } on Object {
      // Seed asset not available - will bootstrap from network
    }
  }

  Future<MobileFootballDataset> loadDataset() async {
    await initialize();
    return MobileFootballDataset.fromJson(
      (await _readGzipMap('active-dataset.json.gz'))!,
    );
  }

  Future<void> saveDataset(MobileFootballDataset dataset) async {
    _validateDataset(dataset);
    final encoded = jsonEncode(dataset.toJson());
    MobileFootballDataset.fromJson(
      (jsonDecode(encoded) as Map).cast<String, Object?>(),
    );
    await _writeAtomicBytes(
      await _file('active-dataset.json.gz'),
      gzip.encode(utf8.encode(encoded)),
    );
  }

  Future<void> saveTrainingSnapshot(MobileFootballDataset dataset) async {
    _validateDataset(dataset);
    await _writeAtomicBytes(
      await _file('training-dataset.json.gz'),
      gzip.encode(utf8.encode(jsonEncode(dataset.toJson()))),
    );
  }

  Future<MobileFootballDataset?> loadTrainingSnapshot() async {
    final value = await _readGzipMap('training-dataset.json.gz');
    return value == null ? null : MobileFootballDataset.fromJson(value);
  }

  Future<void> deleteTrainingSnapshot() async {
    final file = await _file('training-dataset.json.gz');
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<List<FootballOddsSnapshot>> loadOddsSnapshots() async {
    final value = await _readMap('odds-snapshots.json');
    return (value?['snapshots'] as List<Object?>? ?? const [])
        .map(
          (snapshot) => FootballOddsSnapshot.fromJson(
            (snapshot as Map).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<void> saveOddsSnapshot(FootballOddsSnapshot snapshot) async {
    if (!_validOddsSnapshot(snapshot)) {
      throw const FormatException('Invalid football odds snapshot.');
    }
    final snapshots = await loadOddsSnapshots();
    for (final current in snapshots) {
      if (current.matchId == snapshot.matchId &&
          current.capturedAt.toUtc() == snapshot.capturedAt.toUtc() &&
          current.source == snapshot.source &&
          current.line == snapshot.line &&
          current.marketId == snapshot.marketId) {
        if (jsonEncode(current.toJson()) == jsonEncode(snapshot.toJson())) {
          return;
        }
        throw const FormatException('Football odds snapshots are immutable.');
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

  Future<List<FootballWeatherSnapshot>> loadWeatherSnapshots() async {
    final value = await _readMap('weather-snapshots.json');
    return (value?['snapshots'] as List<Object?>? ?? const [])
        .map(
          (snapshot) => FootballWeatherSnapshot.fromJson(
            (snapshot as Map).cast<String, Object?>(),
          ),
        )
        .toList();
  }

  Future<void> saveWeatherSnapshot(FootballWeatherSnapshot snapshot) async {
    if (!_validWeatherSnapshot(snapshot)) {
      throw const FormatException('Invalid football weather snapshot.');
    }
    final snapshots = await loadWeatherSnapshots();
    for (final current in snapshots) {
      if (current.matchId == snapshot.matchId &&
          current.capturedAt.toUtc() == snapshot.capturedAt.toUtc() &&
          current.source == snapshot.source) {
        if (jsonEncode(current.toJson()) == jsonEncode(snapshot.toJson())) {
          return;
        }
        throw const FormatException(
          'Football weather snapshots are immutable.',
        );
      }
    }
    snapshots.add(snapshot);
    snapshots.sort(
      (left, right) => left.capturedAt.compareTo(right.capturedAt),
    );
    if (snapshots.length > 5000) {
      snapshots.removeRange(0, snapshots.length - 5000);
    }
    await _writeAtomicMap('weather-snapshots.json', {
      'schemaVersion': 1,
      'snapshots': snapshots.map((value) => value.toJson()).toList(),
    });
  }

  Future<Map<String, Object?>> exportResearchSnapshots() async {
    final odds = await loadOddsSnapshots();
    final weather = await loadWeatherSnapshots();
    return {
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'oddsSnapshots': odds.map((snapshot) => snapshot.toJson()).toList(),
      'weatherSnapshots': weather.map((snapshot) => snapshot.toJson()).toList(),
    };
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
      throw const FormatException('Unsupported football recovery backup.');
    }
    var modelRestored = false;
    var checkpointRestored = false;
    final modelPayload = payload['activeModel'] as Map?;
    if (modelPayload != null) {
      await saveCandidateAndActivate(
        MobileFootballModel.fromJson(modelPayload.cast<String, Object?>()),
      );
      modelRestored = true;
    }
    final jobPayload = payload['trainingJob'] as Map?;
    if (jobPayload != null) {
      final job = FootballTrainingJob.fromJson(
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

  Future<(int, int)> importResearchSnapshots(
    Map<String, Object?> payload,
  ) async {
    if ((payload['schemaVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('Unsupported research snapshot backup.');
    }
    final importedOdds =
        (payload['oddsSnapshots'] as List<Object?>? ?? const [])
            .map(
              (value) => FootballOddsSnapshot.fromJson(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList();
    final importedWeather =
        (payload['weatherSnapshots'] as List<Object?>? ?? const [])
            .map(
              (value) => FootballWeatherSnapshot.fromJson(
                (value as Map).cast<String, Object?>(),
              ),
            )
            .toList();
    if (importedOdds.any((snapshot) => !_validOddsSnapshot(snapshot)) ||
        importedWeather.any((snapshot) => !_validWeatherSnapshot(snapshot))) {
      throw const FormatException('Research snapshot backup is invalid.');
    }
    final oddsById = {
      for (final snapshot in await loadOddsSnapshots())
        _oddsIdentity(snapshot): snapshot,
    };
    var oddsImported = 0;
    for (final snapshot in importedOdds) {
      final key = _oddsIdentity(snapshot);
      final current = oddsById[key];
      if (current == null) {
        oddsById[key] = snapshot;
        oddsImported++;
      } else if (jsonEncode(current.toJson()) !=
          jsonEncode(snapshot.toJson())) {
        throw const FormatException('Football odds snapshots are immutable.');
      }
    }
    final weatherById = {
      for (final snapshot in await loadWeatherSnapshots())
        _weatherIdentity(snapshot): snapshot,
    };
    var weatherImported = 0;
    for (final snapshot in importedWeather) {
      final key = _weatherIdentity(snapshot);
      final current = weatherById[key];
      if (current == null) {
        weatherById[key] = snapshot;
        weatherImported++;
      } else if (jsonEncode(current.toJson()) !=
          jsonEncode(snapshot.toJson())) {
        throw const FormatException(
          'Football weather snapshots are immutable.',
        );
      }
    }
    final odds = oddsById.values.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    final weather = weatherById.values.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    final retainedOdds = odds.length > 5000
        ? odds.sublist(odds.length - 5000)
        : odds;
    final retainedWeather = weather.length > 5000
        ? weather.sublist(weather.length - 5000)
        : weather;
    await _writeAtomicMap('odds-snapshots.json', {
      'schemaVersion': 1,
      'snapshots': retainedOdds.map((value) => value.toJson()).toList(),
    });
    await _writeAtomicMap('weather-snapshots.json', {
      'schemaVersion': 1,
      'snapshots': retainedWeather.map((value) => value.toJson()).toList(),
    });
    return (oddsImported, weatherImported);
  }

  static bool _validOddsSnapshot(FootballOddsSnapshot snapshot) =>
      snapshot.matchId.isNotEmpty &&
      snapshot.source.isNotEmpty &&
      snapshot.line.isFinite &&
      snapshot.line > 0 &&
      snapshot.overOdds.isFinite &&
      snapshot.overOdds > 1 &&
      snapshot.overOdds <= 1000 &&
      snapshot.underOdds.isFinite &&
      snapshot.underOdds > 1 &&
      snapshot.underOdds <= 1000 &&
      !snapshot.inPlay &&
      snapshot.marketTime != null &&
      snapshot.capturedAt.toUtc().isBefore(snapshot.marketTime!.toUtc());

  static bool _validWeatherSnapshot(FootballWeatherSnapshot snapshot) =>
      snapshot.matchId.isNotEmpty &&
      snapshot.source.isNotEmpty &&
      snapshot.latitude.isFinite &&
      snapshot.latitude >= -90 &&
      snapshot.latitude <= 90 &&
      snapshot.longitude.isFinite &&
      snapshot.longitude >= -180 &&
      snapshot.longitude <= 180 &&
      snapshot.temperatureC.isFinite &&
      snapshot.precipitationProbability.isFinite &&
      snapshot.precipitationProbability >= 0 &&
      snapshot.precipitationProbability <= 100 &&
      snapshot.windSpeedKmh.isFinite &&
      snapshot.windSpeedKmh >= 0 &&
      !snapshot.capturedAt.toUtc().isAfter(snapshot.validAt.toUtc());

  static String _oddsIdentity(FootballOddsSnapshot snapshot) =>
      '${snapshot.matchId}|${snapshot.capturedAt.toUtc().toIso8601String()}|'
      '${snapshot.source}|${snapshot.marketId}|${snapshot.line}';

  static String _weatherIdentity(FootballWeatherSnapshot snapshot) =>
      '${snapshot.matchId}|${snapshot.capturedAt.toUtc().toIso8601String()}|'
      '${snapshot.source}';

  Future<MobileFootballModel?> loadModel() async {
    final value = await _readMap('active-model.json');
    return value == null ? null : MobileFootballModel.fromJson(value);
  }

  Future<void> saveCandidateAndActivate(MobileFootballModel model) async {
    if (model.datasetVersion.isEmpty ||
        model.leagues.length != 5 ||
        model.leagues.map((league) => league.code).toSet().length != 5 ||
        model.leagues.any(
          (league) =>
              league.featureMeans.length != 22 ||
              league.featureScales.length != 22 ||
              league.homeWeights.length != league.featureMeans.length ||
              league.awayWeights.length != league.featureMeans.length ||
              league.totalWeights.length != league.featureMeans.length ||
              [
                league.homeIntercept,
                league.awayIntercept,
                league.totalIntercept,
                league.mae,
                league.baselineMae,
                league.brierOver95,
                league.baselineBrierOver95,
                league.dispersion,
                ...league.featureMeans,
                ...league.featureScales,
                ...league.homeWeights,
                ...league.awayWeights,
                ...league.totalWeights,
              ].any((value) => !value.isFinite),
        )) {
      throw const FormatException('Invalid mobile football model.');
    }
    final encoded = jsonEncode(model.toJson());
    final verified = MobileFootballModel.fromJson(
      (jsonDecode(encoded) as Map).cast<String, Object?>(),
    );
    final candidate = await _file('candidate-model.json');
    await _writeAtomic(candidate, encoded);
    final active = await _file('active-model.json');
    try {
      await _writeAtomic(active, encoded);
      final activated = MobileFootballModel.fromJson(
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

  Future<FootballTrainingJob?> loadJob() async {
    final value = await _readMap('training-job.json');
    return value == null ? null : FootballTrainingJob.fromJson(value);
  }

  Future<void> saveJob(FootballTrainingJob job) =>
      _writeAtomicMap('training-job.json', job.toJson());

  Future<FeatureAblationReport?> loadFeatureAblation() async {
    final value = await _readMap('feature-ablation.json');
    return value == null ? null : FeatureAblationReport.fromJson(value);
  }

  Future<void> saveFeatureAblation(FeatureAblationReport report) =>
      _writeAtomicMap('feature-ablation.json', report.toJson());

  Future<bool> needsTraining() async {
    final marker = await _file('training-needed');
    return marker.existsSync();
  }

  Future<void> markTrainingNeeded() async {
    final marker = await _file('training-needed');
    await marker.writeAsString(DateTime.now().toIso8601String(), flush: true);
  }

  Future<void> clearTrainingNeeded() async {
    final marker = await _file('training-needed');
    if (marker.existsSync()) {
      await marker.delete();
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

  Future<void> touchTrainingLock() async {
    final lock = await _file('training.lock');
    if (lock.existsSync()) {
      await lock.setLastModified(DateTime.now());
    }
  }

  Future<void> releaseTrainingLock() async {
    final lock = await _file('training.lock');
    if (lock.existsSync()) {
      await lock.delete();
    }
  }

  void _validateDataset(MobileFootballDataset dataset) {
    final reasons = datasetViolations(dataset);
    if (reasons.isNotEmpty) {
      throw FormatException(
        'Invalid mobile football dataset: ${reasons.join('; ')}',
      );
    }
  }

  /// Human-readable reasons why [dataset] may not be persisted.
  ///
  /// Empty means the dataset is safe to write.
  static List<String> datasetViolations(MobileFootballDataset dataset) {
    final divisions = {
      for (final league in dataset.leagues) league.code,
      for (final league in dataset.leagues) league.supportCode,
    };
    final codes = dataset.leagues.map((league) => league.code).toSet();
    final reasons = <String>[];
    if (dataset.schemaVersion < 1 ||
        dataset.schemaVersion > supportedSchemaVersion) {
      reasons.add('schemaVersion ${dataset.schemaVersion}');
    }
    if (dataset.datasetVersion.isEmpty) {
      reasons.add('datasetVersion 為空');
    }
    if (dataset.leagues.length != 5 || codes.length != 5) {
      reasons.add('聯賽數 ${dataset.leagues.length}');
    }
    if (dataset.rows.isEmpty) {
      reasons.add('rows 為空');
    }
    final matchIds = <String>{};
    for (final row in dataset.rows) {
      if (!row.isComplete ||
          row.matchId.isEmpty ||
          !divisions.contains(row.division) ||
          DateTime.tryParse(row.date) == null ||
          row.homeCorners! < 0 ||
          row.awayCorners! < 0 ||
          !matchIds.add(row.matchId)) {
        reasons.add('賽果列無效 ${row.matchId}');
        break;
      }
    }
    for (final row in dataset.fixtures) {
      if (row.isComplete ||
          !codes.contains(row.division) ||
          DateTime.tryParse(row.date) == null) {
        reasons.add('賽程列無效 ${row.matchId}');
        break;
      }
    }
    return reasons;
  }

  Future<Map<String, Object?>?> _readGzipMap(String name) async {
    final file = await _file(name);
    if (!file.existsSync()) {
      return null;
    }
    try {
      return (jsonDecode(utf8.decode(gzip.decode(await file.readAsBytes())))
              as Map)
          .cast<String, Object?>();
    } on Object {
      final backup = File('${file.path}.backup');
      if (!backup.existsSync()) {
        rethrow;
      }
      final value =
          (jsonDecode(utf8.decode(gzip.decode(await backup.readAsBytes())))
                  as Map)
              .cast<String, Object?>();
      await file.delete();
      await backup.copy(file.path);
      return value;
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

  Future<void> _writeAtomicMap(String name, Map<String, Object?> value) async {
    await _writeAtomic(await _file(name), jsonEncode(value));
  }

  Future<void> _writeAtomic(File active, String contents) async {
    await _writeAtomicBytes(active, utf8.encode(contents));
  }

  Future<void> _writeAtomicBytes(File active, List<int> contents) async {
    final staging = File('${active.path}.staging');
    final backup = File('${active.path}.backup');
    await staging.writeAsBytes(contents, flush: true);
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
