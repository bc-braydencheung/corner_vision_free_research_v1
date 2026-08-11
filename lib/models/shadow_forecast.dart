class ShadowForecast {
  const ShadowForecast({
    required this.id,
    required this.matchId,
    required this.leagueCode,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.matchDate,
    required this.capturedAt,
    required this.modelVersion,
    required this.expectedTotalCorners,
    required this.over9_5Probability,
    required this.referenceMae,
    required this.referenceBrier,
    this.actualTotalCorners,
    this.settledAt,
  });

  factory ShadowForecast.fromJson(Map<String, Object?> json) {
    return ShadowForecast(
      id: json['id'] as String,
      matchId: json['matchId'] as String,
      leagueCode: json['leagueCode'] as String,
      leagueName: json['leagueName'] as String,
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      matchDate: DateTime.parse(json['matchDate'] as String),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      modelVersion: json['modelVersion'] as String,
      expectedTotalCorners: (json['expectedTotalCorners'] as num).toDouble(),
      over9_5Probability: (json['over9_5Probability'] as num).toDouble(),
      referenceMae: (json['referenceMae'] as num).toDouble(),
      referenceBrier: (json['referenceBrier'] as num).toDouble(),
      actualTotalCorners: (json['actualTotalCorners'] as num?)?.toInt(),
      settledAt: json['settledAt'] == null
          ? null
          : DateTime.parse(json['settledAt'] as String),
    );
  }

  final String id;
  final String matchId;
  final String leagueCode;
  final String leagueName;
  final String homeTeam;
  final String awayTeam;
  final DateTime matchDate;
  final DateTime capturedAt;
  final String modelVersion;
  final double expectedTotalCorners;
  final double over9_5Probability;
  final double referenceMae;
  final double referenceBrier;
  final int? actualTotalCorners;
  final DateTime? settledAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'matchId': matchId,
    'leagueCode': leagueCode,
    'leagueName': leagueName,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'matchDate': matchDate.toUtc().toIso8601String(),
    'capturedAt': capturedAt.toUtc().toIso8601String(),
    'modelVersion': modelVersion,
    'expectedTotalCorners': expectedTotalCorners,
    'over9_5Probability': over9_5Probability,
    'referenceMae': referenceMae,
    'referenceBrier': referenceBrier,
    'actualTotalCorners': actualTotalCorners,
    'settledAt': settledAt?.toUtc().toIso8601String(),
  };

  ShadowForecast settle(int totalCorners, DateTime timestamp) {
    if (actualTotalCorners != null) {
      return this;
    }
    return ShadowForecast(
      id: id,
      matchId: matchId,
      leagueCode: leagueCode,
      leagueName: leagueName,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      matchDate: matchDate,
      capturedAt: capturedAt,
      modelVersion: modelVersion,
      expectedTotalCorners: expectedTotalCorners,
      over9_5Probability: over9_5Probability,
      referenceMae: referenceMae,
      referenceBrier: referenceBrier,
      actualTotalCorners: totalCorners,
      settledAt: timestamp,
    );
  }
}

class ShadowHealth {
  const ShadowHealth({
    required this.status,
    required this.message,
    required this.totalForecasts,
    required this.settledForecasts,
    required this.openForecasts,
    required this.mae,
    required this.brierOver9_5,
    required this.referenceMae,
    required this.referenceBrier,
  });

  static const empty = ShadowHealth(
    status: 'insufficient',
    message: '尚未累積前瞻shadow預測。',
    totalForecasts: 0,
    settledForecasts: 0,
    openForecasts: 0,
    mae: 0,
    brierOver9_5: 0,
    referenceMae: 0,
    referenceBrier: 0,
  );

  final String status;
  final String message;
  final int totalForecasts;
  final int settledForecasts;
  final int openForecasts;
  final double mae;
  final double brierOver9_5;
  final double referenceMae;
  final double referenceBrier;

  bool get suspendTrading => status == 'stop';
}
