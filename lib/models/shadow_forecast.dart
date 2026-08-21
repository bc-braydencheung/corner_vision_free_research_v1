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
    this.marketOverProbability,
    this.uncalibratedOver9_5Probability,
    this.calibratedOver9_5Probability,
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
      marketOverProbability: (json['marketOverProbability'] as num?)
          ?.toDouble(),
      uncalibratedOver9_5Probability:
          (json['uncalibratedOver9_5Probability'] as num?)?.toDouble(),
      calibratedOver9_5Probability:
          (json['calibratedOver9_5Probability'] as num?)?.toDouble(),
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

  /// Vig-free market probability of the same event at capture time.
  ///
  /// Absent whenever the free feed carried no usable pair of prices, which is
  /// why the market anchor is learned only from the records that have it.
  final double? marketOverProbability;

  /// The same probability before the calibrator was applied to it.
  ///
  /// Calibration must be fitted on what the model said on its own: fitting it
  /// on [over9_5Probability], which already carries the calibrator that was
  /// live when the forecast was captured, would compound one mapping on top of
  /// another every time the calibrator is refitted. Absent on records written
  /// before this field existed and on records that did not come from the HKJC
  /// corner model, so those never enter a fit.
  final double? uncalibratedOver9_5Probability;

  /// The probability after calibration but before the residual model or the
  /// market shrinkage replaced it.
  ///
  /// The residual model is fitted on exactly the input it corrects; using
  /// [over9_5Probability] instead would feed the residual model its own output
  /// once it had been adopted.
  final double? calibratedOver9_5Probability;
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
    'marketOverProbability': marketOverProbability,
    'uncalibratedOver9_5Probability': uncalibratedOver9_5Probability,
    'calibratedOver9_5Probability': calibratedOver9_5Probability,
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
      marketOverProbability: marketOverProbability,
      uncalibratedOver9_5Probability: uncalibratedOver9_5Probability,
      calibratedOver9_5Probability: calibratedOver9_5Probability,
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
