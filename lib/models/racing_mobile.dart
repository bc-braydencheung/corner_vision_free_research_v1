class RacingTrainingRow {
  const RacingTrainingRow({
    required this.raceId,
    required this.date,
    required this.fieldSize,
    required this.won,
    required this.placed,
    required this.features,
  });

  factory RacingTrainingRow.fromJson(List<Object?> json) {
    return RacingTrainingRow(
      raceId: json[0] as String,
      date: json[1] as String,
      fieldSize: (json[2] as num).toInt(),
      won: (json[3] as num).toInt(),
      placed: (json[4] as num).toInt(),
      features: json
          .skip(5)
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
    );
  }

  final String raceId;
  final String date;
  final int fieldSize;
  final int won;
  final int placed;
  final List<double> features;

  List<Object> toJson() => [
    raceId,
    date,
    fieldSize,
    won,
    placed,
    ...features.map((value) => double.parse(value.toStringAsFixed(6))),
  ];
}

class RacingOddsSnapshot {
  const RacingOddsSnapshot({
    required this.raceId,
    required this.capturedAt,
    required this.source,
    required this.oddsByHorse,
    this.raceTime,
    this.isFinal = false,
  });

  factory RacingOddsSnapshot.fromJson(Map<String, Object?> json) {
    return RacingOddsSnapshot(
      raceId: json['raceId'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      source: json['source'] as String,
      oddsByHorse: (json['oddsByHorse'] as Map).map(
        (key, value) => MapEntry(key as String, (value as num).toDouble()),
      ),
      raceTime: json['raceTime'] == null
          ? null
          : DateTime.parse(json['raceTime'] as String),
      isFinal: json['isFinal'] as bool? ?? false,
    );
  }

  final String raceId;
  final DateTime capturedAt;
  final String source;
  final Map<String, double> oddsByHorse;
  final DateTime? raceTime;
  final bool isFinal;

  Map<String, Object?> toJson() => {
    'raceId': raceId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'source': source,
    'oddsByHorse': oddsByHorse,
    'raceTime': raceTime?.toUtc().toIso8601String(),
    'isFinal': isFinal,
  };
}

class MobileEntityState {
  MobileEntityState({
    this.starts = 0,
    this.wins = 0,
    this.places = 0,
    this.finishTotal = 0,
    this.lastDate = '',
    List<double>? recent,
    Map<int, int>? distanceStarts,
    Map<int, int>? distanceWins,
  }) : recent = recent ?? [],
       distanceStarts = distanceStarts ?? {},
       distanceWins = distanceWins ?? {};

  factory MobileEntityState.fromJson(List<Object?> json) {
    return MobileEntityState(
      starts: (json[0] as num).toInt(),
      wins: (json[1] as num).toInt(),
      places: (json[2] as num).toInt(),
      finishTotal: (json[3] as num).toDouble(),
      lastDate: json[4] as String,
      recent: (json[5] as List<Object?>)
          .map((value) => (value as num).toDouble())
          .toList(),
      distanceStarts: (json[6] as Map).map(
        (key, value) =>
            MapEntry(int.parse(key as String), (value as num).toInt()),
      ),
      distanceWins: (json[7] as Map).map(
        (key, value) =>
            MapEntry(int.parse(key as String), (value as num).toInt()),
      ),
    );
  }

  int starts;
  int wins;
  int places;
  double finishTotal;
  String lastDate;
  final List<double> recent;
  final Map<int, int> distanceStarts;
  final Map<int, int> distanceWins;

  double get finishScore => starts == 0 ? 0.5 : finishTotal / starts;
  double get recentScore => recent.isEmpty
      ? finishScore
      : recent.reduce((left, right) => left + right) / recent.length;

  void update({
    required int won,
    required int placed,
    required double score,
    required String date,
  }) {
    starts++;
    wins += won;
    places += placed;
    finishTotal += score;
    recent
      ..add(score)
      ..removeRange(0, recent.length > 6 ? recent.length - 6 : 0);
    lastDate = date;
  }

  List<Object> toJson() => [
    starts,
    wins,
    places,
    double.parse(finishTotal.toStringAsFixed(6)),
    lastDate,
    recent,
    distanceStarts.map((key, value) => MapEntry('$key', value)),
    distanceWins.map((key, value) => MapEntry('$key', value)),
  ];
}

class MobileRacingDataset {
  MobileRacingDataset({
    required this.schemaVersion,
    required this.datasetVersion,
    required this.trainedThrough,
    required this.featureNames,
    required this.rows,
    required this.horses,
    required this.jockeys,
    required this.trainers,
    Map<String, List<String>>? horseNames,
    List<Map<String, Object?>>? results,
  }) : horseNames = horseNames ?? {},
       results = results ?? [];

  factory MobileRacingDataset.fromJson(Map<String, Object?> json) {
    Map<String, MobileEntityState> states(Object? value) => (value as Map).map(
      (key, state) => MapEntry(
        key as String,
        MobileEntityState.fromJson(state as List<Object?>),
      ),
    );

    return MobileRacingDataset(
      schemaVersion: (json['schemaVersion'] as num).toInt(),
      datasetVersion: json['datasetVersion'] as String,
      trainedThrough: json['trainedThrough'] as String,
      featureNames: (json['featureNames'] as List<Object?>)
          .cast<String>()
          .toList(growable: false),
      rows: (json['rows'] as List<Object?>)
          .map((value) => RacingTrainingRow.fromJson(value as List<Object?>))
          .toList(),
      horses: states(json['horses']),
      jockeys: states(json['jockeys']),
      trainers: states(json['trainers']),
      horseNames: (json['horseNames'] as Map? ?? const {}).map(
        (key, value) => MapEntry(
          key as String,
          (value as List<Object?>).cast<String>().toList(),
        ),
      ),
      results: (json['results'] as List<Object?>? ?? const [])
          .map((value) => (value as Map).cast<String, Object?>())
          .toList(),
    );
  }

  final int schemaVersion;
  String datasetVersion;
  String trainedThrough;
  final List<String> featureNames;
  final List<RacingTrainingRow> rows;
  final Map<String, MobileEntityState> horses;
  final Map<String, MobileEntityState> jockeys;
  final Map<String, MobileEntityState> trainers;
  final Map<String, List<String>> horseNames;
  final List<Map<String, Object?>> results;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'datasetVersion': datasetVersion,
    'trainedThrough': trainedThrough,
    'featureNames': featureNames,
    'rows': rows.map((row) => row.toJson()).toList(),
    'horses': horses.map((key, value) => MapEntry(key, value.toJson())),
    'jockeys': jockeys.map((key, value) => MapEntry(key, value.toJson())),
    'trainers': trainers.map((key, value) => MapEntry(key, value.toJson())),
    'horseNames': horseNames,
    'results': results,
  };
}

class MobileRacingModel {
  const MobileRacingModel({
    required this.version,
    required this.datasetVersion,
    required this.trainedThrough,
    required this.winWeights,
    required this.winIntercept,
    required this.placeWeights,
    required this.placeIntercept,
    required this.useWinModel,
    required this.usePlaceModel,
    required this.trainingRaces,
    required this.holdoutRaces,
    required this.winLogLoss,
    required this.baselineWinLogLoss,
    required this.winBrier,
    required this.placeBrier,
    required this.baselinePlaceBrier,
  });

  factory MobileRacingModel.fromJson(Map<String, Object?> json) {
    List<double> weights(String key) => (json[key] as List<Object?>)
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
    return MobileRacingModel(
      version: json['version'] as String,
      datasetVersion: json['datasetVersion'] as String,
      trainedThrough: json['trainedThrough'] as String,
      winWeights: weights('winWeights'),
      winIntercept: (json['winIntercept'] as num).toDouble(),
      placeWeights: weights('placeWeights'),
      placeIntercept: (json['placeIntercept'] as num).toDouble(),
      useWinModel: json['useWinModel'] as bool,
      usePlaceModel: json['usePlaceModel'] as bool,
      trainingRaces: (json['trainingRaces'] as num).toInt(),
      holdoutRaces: (json['holdoutRaces'] as num).toInt(),
      winLogLoss: (json['winLogLoss'] as num).toDouble(),
      baselineWinLogLoss: (json['baselineWinLogLoss'] as num).toDouble(),
      winBrier: (json['winBrier'] as num).toDouble(),
      placeBrier: (json['placeBrier'] as num).toDouble(),
      baselinePlaceBrier: (json['baselinePlaceBrier'] as num).toDouble(),
    );
  }

  final String version;
  final String datasetVersion;
  final String trainedThrough;
  final List<double> winWeights;
  final double winIntercept;
  final List<double> placeWeights;
  final double placeIntercept;
  final bool useWinModel;
  final bool usePlaceModel;
  final int trainingRaces;
  final int holdoutRaces;
  final double winLogLoss;
  final double baselineWinLogLoss;
  final double winBrier;
  final double placeBrier;
  final double baselinePlaceBrier;

  Map<String, Object?> toJson() => {
    'version': version,
    'datasetVersion': datasetVersion,
    'trainedThrough': trainedThrough,
    'winWeights': winWeights,
    'winIntercept': winIntercept,
    'placeWeights': placeWeights,
    'placeIntercept': placeIntercept,
    'useWinModel': useWinModel,
    'usePlaceModel': usePlaceModel,
    'trainingRaces': trainingRaces,
    'holdoutRaces': holdoutRaces,
    'winLogLoss': winLogLoss,
    'baselineWinLogLoss': baselineWinLogLoss,
    'winBrier': winBrier,
    'placeBrier': placeBrier,
    'baselinePlaceBrier': baselinePlaceBrier,
  };
}

class RacingTrainingJob {
  const RacingTrainingJob({
    required this.id,
    required this.datasetVersion,
    required this.status,
    required this.stage,
    required this.progress,
    required this.epoch,
    required this.updatedAt,
    this.error = '',
    this.checkpoint = const {},
  });

  factory RacingTrainingJob.fromJson(Map<String, Object?> json) {
    return RacingTrainingJob(
      id: json['id'] as String,
      datasetVersion: json['datasetVersion'] as String,
      status: json['status'] as String,
      stage: json['stage'] as String,
      progress: (json['progress'] as num).toDouble(),
      epoch: (json['epoch'] as num? ?? 0).toInt(),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      error: json['error'] as String? ?? '',
      checkpoint: (json['checkpoint'] as Map? ?? const {})
          .cast<String, Object?>(),
    );
  }

  final String id;
  final String datasetVersion;
  final String status;
  final String stage;
  final double progress;
  final int epoch;
  final DateTime updatedAt;
  final String error;
  final Map<String, Object?> checkpoint;

  bool get isUnfinished =>
      status == 'queued' || status == 'training' || status == 'paused';

  bool get isPaused => status == 'paused';

  Map<String, Object?> toJson() => {
    'id': id,
    'datasetVersion': datasetVersion,
    'status': status,
    'stage': stage,
    'progress': progress,
    'epoch': epoch,
    'updatedAt': updatedAt.toIso8601String(),
    'error': error,
    'checkpoint': checkpoint,
  };
}
