import '../services/walk_forward.dart';

class FootballLeagueConfig {
  const FootballLeagueConfig({
    required this.code,
    required this.name,
    required this.supportCode,
    required this.supportName,
  });

  factory FootballLeagueConfig.fromJson(Map<String, Object?> json) {
    return FootballLeagueConfig(
      code: json['code'] as String,
      name: json['name'] as String,
      supportCode: json['supportCode'] as String,
      supportName: json['supportName'] as String,
    );
  }

  final String code;
  final String name;
  final String supportCode;
  final String supportName;

  Map<String, Object?> toJson() => {
    'code': code,
    'name': name,
    'supportCode': supportCode,
    'supportName': supportName,
  };
}

class FootballOddsSnapshot {
  const FootballOddsSnapshot({
    required this.matchId,
    required this.capturedAt,
    required this.source,
    required this.line,
    required this.overOdds,
    required this.underOdds,
    this.marketId,
    this.eventName,
    this.marketName,
    this.marketType = 'MATCH_CORNERS',
    this.marketTime,
    this.inPlay = false,
    this.isClosing = false,
  });

  factory FootballOddsSnapshot.fromJson(Map<String, Object?> json) {
    return FootballOddsSnapshot(
      matchId: json['matchId'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      source: json['source'] as String,
      line: (json['line'] as num).toDouble(),
      overOdds: (json['overOdds'] as num).toDouble(),
      underOdds: (json['underOdds'] as num).toDouble(),
      marketId: json['marketId'] as String?,
      eventName: json['eventName'] as String?,
      marketName: json['marketName'] as String?,
      marketType: json['marketType'] as String? ?? 'MATCH_CORNERS',
      marketTime: json['marketTime'] == null
          ? null
          : DateTime.parse(json['marketTime'] as String),
      inPlay: json['inPlay'] as bool? ?? false,
      isClosing: json['isClosing'] as bool? ?? false,
    );
  }

  final String matchId;
  final DateTime capturedAt;
  final String source;
  final double line;
  final double overOdds;
  final double underOdds;
  final String? marketId;
  final String? eventName;
  final String? marketName;
  final String marketType;
  final DateTime? marketTime;
  final bool inPlay;
  final bool isClosing;

  double get marketOverProbability {
    final over = 1 / overOdds;
    final under = 1 / underOdds;
    return over / (over + under);
  }

  Map<String, Object?> toJson() => {
    'matchId': matchId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'source': source,
    'line': line,
    'overOdds': overOdds,
    'underOdds': underOdds,
    'marketId': marketId,
    'eventName': eventName,
    'marketName': marketName,
    'marketType': marketType,
    'marketTime': marketTime?.toUtc().toIso8601String(),
    'inPlay': inPlay,
    'isClosing': isClosing,
  };
}

class FootballWeatherSnapshot {
  const FootballWeatherSnapshot({
    required this.matchId,
    required this.capturedAt,
    required this.validAt,
    required this.source,
    required this.latitude,
    required this.longitude,
    required this.temperatureC,
    required this.precipitationProbability,
    required this.windSpeedKmh,
  });

  factory FootballWeatherSnapshot.fromJson(Map<String, Object?> json) {
    return FootballWeatherSnapshot(
      matchId: json['matchId'] as String,
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      validAt: DateTime.parse(json['validAt'] as String),
      source: json['source'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      temperatureC: (json['temperatureC'] as num).toDouble(),
      precipitationProbability: (json['precipitationProbability'] as num)
          .toDouble(),
      windSpeedKmh: (json['windSpeedKmh'] as num).toDouble(),
    );
  }

  final String matchId;
  final DateTime capturedAt;
  final DateTime validAt;
  final String source;
  final double latitude;
  final double longitude;
  final double temperatureC;
  final double precipitationProbability;
  final double windSpeedKmh;

  Map<String, Object?> toJson() => {
    'matchId': matchId,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'validAt': validAt.toUtc().toIso8601String(),
    'source': source,
    'latitude': latitude,
    'longitude': longitude,
    'temperatureC': temperatureC,
    'precipitationProbability': precipitationProbability,
    'windSpeedKmh': windSpeedKmh,
  };
}

class FootballMatchRecord {
  const FootballMatchRecord({
    required this.division,
    required this.date,
    required this.homeTeam,
    required this.awayTeam,
    this.homeCorners,
    this.awayCorners,
    this.homeGoals,
    this.awayGoals,
    this.homeShots,
    this.awayShots,
    this.homeShotsOnTarget,
    this.awayShotsOnTarget,
    this.homeOdds,
    this.drawOdds,
    this.awayOdds,
    this.over25Odds,
    this.under25Odds,
    this.referee,
  });

  factory FootballMatchRecord.fromCompact(List<Object?> values) {
    double? number(int index) =>
        values.length > index ? (values[index] as num?)?.toDouble() : null;
    int? integer(int index) => number(index)?.toInt();
    return FootballMatchRecord(
      division: values[0] as String,
      date: values[1] as String,
      homeTeam: values[2] as String,
      awayTeam: values[3] as String,
      homeCorners: integer(4),
      awayCorners: integer(5),
      homeGoals: integer(6),
      awayGoals: integer(7),
      homeShots: integer(8),
      awayShots: integer(9),
      homeShotsOnTarget: integer(10),
      awayShotsOnTarget: integer(11),
      homeOdds: number(12),
      drawOdds: number(13),
      awayOdds: number(14),
      over25Odds: number(15),
      under25Odds: number(16),
      referee: values.length > 17 ? values[17] as String? : null,
    );
  }

  final String division;
  final String date;
  final String homeTeam;
  final String awayTeam;
  final int? homeCorners;
  final int? awayCorners;
  final int? homeGoals;
  final int? awayGoals;
  final int? homeShots;
  final int? awayShots;
  final int? homeShotsOnTarget;
  final int? awayShotsOnTarget;
  final double? homeOdds;
  final double? drawOdds;
  final double? awayOdds;
  final double? over25Odds;
  final double? under25Odds;

  /// Match official as spelled in the free history, when the source has it.
  final String? referee;

  bool get isComplete => homeCorners != null && awayCorners != null;

  String get matchId => '$division:$date:$homeTeam:$awayTeam';

  List<Object?> toCompact() => [
    division,
    date,
    homeTeam,
    awayTeam,
    homeCorners,
    awayCorners,
    homeGoals,
    awayGoals,
    homeShots,
    awayShots,
    homeShotsOnTarget,
    awayShotsOnTarget,
    homeOdds,
    drawOdds,
    awayOdds,
    over25Odds,
    under25Odds,
    referee,
  ];
}

class MobileFootballDataset {
  const MobileFootballDataset({
    required this.schemaVersion,
    required this.datasetVersion,
    required this.generatedAt,
    required this.leagues,
    required this.rows,
    required this.fixtures,
  });

  factory MobileFootballDataset.fromJson(Map<String, Object?> json) {
    return MobileFootballDataset(
      schemaVersion: (json['schemaVersion'] as num).toInt(),
      datasetVersion: json['datasetVersion'] as String,
      generatedAt: json['generatedAt'] as String,
      leagues: (json['leagues'] as List<Object?>)
          .map(
            (item) => FootballLeagueConfig.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      rows: (json['rows'] as List<Object?>)
          .map(
            (item) => FootballMatchRecord.fromCompact((item as List<Object?>)),
          )
          .toList(growable: false),
      fixtures: (json['fixtures'] as List<Object?>? ?? const [])
          .map(
            (item) => FootballMatchRecord.fromCompact((item as List<Object?>)),
          )
          .toList(growable: false),
    );
  }

  final int schemaVersion;
  final String datasetVersion;
  final String generatedAt;
  final List<FootballLeagueConfig> leagues;
  final List<FootballMatchRecord> rows;
  final List<FootballMatchRecord> fixtures;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'datasetVersion': datasetVersion,
    'generatedAt': generatedAt,
    'leagues': leagues.map((league) => league.toJson()).toList(),
    'rows': rows.map((row) => row.toCompact()).toList(),
    'fixtures': fixtures.map((row) => row.toCompact()).toList(),
  };

  String trainedThrough(String division) {
    final dates = rows
        .where((row) => row.division == division)
        .map((row) => row.date);
    return dates.isEmpty
        ? ''
        : dates.reduce(
            (left, right) => left.compareTo(right) > 0 ? left : right,
          );
  }
}

class FootballTrainingRow {
  const FootballTrainingRow({
    required this.matchId,
    required this.date,
    required this.features,
    required this.homeCorners,
    required this.awayCorners,
    required this.baselineHome,
    required this.baselineAway,
  });

  final String matchId;
  final String date;
  final List<double> features;
  final int homeCorners;
  final int awayCorners;
  final double baselineHome;
  final double baselineAway;

  int get totalCorners => homeCorners + awayCorners;
  double get baselineTotal => baselineHome + baselineAway;
}

class MobileFootballLeagueModel {
  const MobileFootballLeagueModel({
    required this.code,
    required this.featureMeans,
    required this.featureScales,
    required this.homeWeights,
    required this.homeIntercept,
    required this.awayWeights,
    required this.awayIntercept,
    required this.totalWeights,
    required this.totalIntercept,
    required this.useModel,
    required this.trainingMatches,
    required this.holdoutMatches,
    required this.mae,
    required this.baselineMae,
    required this.brierOver95,
    required this.baselineBrierOver95,
    required this.dispersion,
    this.walkForward,
  });

  factory MobileFootballLeagueModel.fromJson(Map<String, Object?> json) {
    List<double> values(String key) => (json[key] as List<Object?>)
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
    return MobileFootballLeagueModel(
      code: json['code'] as String,
      featureMeans: values('featureMeans'),
      featureScales: values('featureScales'),
      homeWeights: values('homeWeights'),
      homeIntercept: (json['homeIntercept'] as num).toDouble(),
      awayWeights: values('awayWeights'),
      awayIntercept: (json['awayIntercept'] as num).toDouble(),
      totalWeights: values('totalWeights'),
      totalIntercept: (json['totalIntercept'] as num).toDouble(),
      useModel: json['useModel'] as bool,
      trainingMatches: (json['trainingMatches'] as num).toInt(),
      holdoutMatches: (json['holdoutMatches'] as num).toInt(),
      mae: (json['mae'] as num).toDouble(),
      baselineMae: (json['baselineMae'] as num).toDouble(),
      brierOver95: (json['brierOver95'] as num).toDouble(),
      baselineBrierOver95: (json['baselineBrierOver95'] as num).toDouble(),
      dispersion: (json['dispersion'] as num).toDouble(),
      walkForward: json['walkForward'] == null
          ? null
          : WalkForwardReport.fromJson(
              (json['walkForward'] as Map).cast<String, Object?>(),
            ),
    );
  }

  final String code;
  final List<double> featureMeans;
  final List<double> featureScales;
  final List<double> homeWeights;
  final double homeIntercept;
  final List<double> awayWeights;
  final double awayIntercept;
  final List<double> totalWeights;
  final double totalIntercept;
  final bool useModel;
  final int trainingMatches;
  final int holdoutMatches;
  final double mae;
  final double baselineMae;
  final double brierOver95;
  final double baselineBrierOver95;
  final double dispersion;

  /// Purged walk-forward result, when the history was long enough to run it.
  final WalkForwardReport? walkForward;

  Map<String, Object?> toJson() => {
    'code': code,
    'featureMeans': featureMeans,
    'featureScales': featureScales,
    'homeWeights': homeWeights,
    'homeIntercept': homeIntercept,
    'awayWeights': awayWeights,
    'awayIntercept': awayIntercept,
    'totalWeights': totalWeights,
    'totalIntercept': totalIntercept,
    'useModel': useModel,
    'trainingMatches': trainingMatches,
    'holdoutMatches': holdoutMatches,
    'mae': mae,
    'baselineMae': baselineMae,
    'brierOver95': brierOver95,
    'baselineBrierOver95': baselineBrierOver95,
    'dispersion': dispersion,
    if (walkForward != null) 'walkForward': walkForward!.toJson(),
  };
}

class MobileFootballModel {
  const MobileFootballModel({
    required this.version,
    required this.datasetVersion,
    required this.trainedThrough,
    required this.leagues,
  });

  factory MobileFootballModel.fromJson(Map<String, Object?> json) {
    return MobileFootballModel(
      version: json['version'] as String,
      datasetVersion: json['datasetVersion'] as String,
      trainedThrough: (json['trainedThrough'] as Map).cast<String, String>(),
      leagues: (json['leagues'] as List<Object?>)
          .map(
            (item) => MobileFootballLeagueModel.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
    );
  }

  final String version;
  final String datasetVersion;
  final Map<String, String> trainedThrough;
  final List<MobileFootballLeagueModel> leagues;

  Map<String, Object?> toJson() => {
    'version': version,
    'datasetVersion': datasetVersion,
    'trainedThrough': trainedThrough,
    'leagues': leagues.map((league) => league.toJson()).toList(),
  };
}

class FootballTrainingJob {
  const FootballTrainingJob({
    required this.id,
    required this.datasetVersion,
    required this.status,
    required this.stage,
    required this.progress,
    required this.epoch,
    required this.updatedAt,
    this.error,
    this.checkpoint = const {},
  });

  factory FootballTrainingJob.fromJson(Map<String, Object?> json) {
    return FootballTrainingJob(
      id: json['id'] as String,
      datasetVersion: json['datasetVersion'] as String,
      status: json['status'] as String,
      stage: json['stage'] as String,
      progress: (json['progress'] as num).toDouble(),
      epoch: (json['epoch'] as num).toInt(),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      error: json['error'] as String?,
      checkpoint: (json['checkpoint'] as Map<Object?, Object?>? ?? const {})
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
  final String? error;
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
