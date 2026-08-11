class ForecastData {
  const ForecastData({
    required this.dataVersion,
    required this.generatedAt,
    required this.leagues,
    required this.settlementResults,
    required this.racing,
    required this.disclaimer,
  });

  factory ForecastData.fromJson(Map<String, Object?> json) {
    return ForecastData(
      dataVersion: json['dataVersion'] as String,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      leagues: (json['leagues'] as List<Object?>)
          .map(
            (item) => LeagueForecastData.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      settlementResults:
          (json['settlementResults'] as List<Object?>? ?? const [])
              .map(
                (item) =>
                    MatchResult.fromJson((item as Map).cast<String, Object?>()),
              )
              .toList(growable: false),
      racing: RacingSummary.fromJson(
        (json['racing'] as Map).cast<String, Object?>(),
      ),
      disclaimer: json['disclaimer'] as String,
    );
  }

  final String dataVersion;
  final DateTime generatedAt;
  final List<LeagueForecastData> leagues;
  final List<MatchResult> settlementResults;
  final RacingSummary racing;
  final String disclaimer;

  ForecastData withSettlementResults(List<MatchResult> results) {
    return ForecastData(
      dataVersion: dataVersion,
      generatedAt: generatedAt,
      leagues: leagues,
      settlementResults: results,
      racing: racing,
      disclaimer: disclaimer,
    );
  }

  ForecastData withRacing(RacingSummary value) {
    return ForecastData(
      dataVersion: dataVersion,
      generatedAt: generatedAt,
      leagues: leagues,
      settlementResults: settlementResults,
      racing: value,
      disclaimer: disclaimer,
    );
  }

  ForecastData withFootball({
    required List<LeagueForecastData> value,
    required List<MatchResult> results,
  }) {
    return ForecastData(
      dataVersion: dataVersion,
      generatedAt: generatedAt,
      leagues: value,
      settlementResults: results,
      racing: racing,
      disclaimer: disclaimer,
    );
  }

  LeagueForecastData league(String code) {
    return leagues.firstWhere(
      (league) => league.code == code,
      orElse: () => leagues.first,
    );
  }
}

class LeagueForecastData {
  const LeagueForecastData({
    required this.code,
    required this.name,
    required this.supportName,
    required this.status,
    required this.model,
    required this.forecasts,
    required this.recentBacktests,
  });

  factory LeagueForecastData.fromJson(Map<String, Object?> json) {
    return LeagueForecastData(
      code: json['code'] as String,
      name: json['name'] as String,
      supportName: json['supportName'] as String,
      status: json['status'] as String,
      model: ModelSummary.fromJson(
        (json['model'] as Map).cast<String, Object?>(),
      ),
      forecasts: _predictions(json['forecasts']),
      recentBacktests: _predictions(json['recentBacktests']),
    );
  }

  final String code;
  final String name;
  final String supportName;
  final String status;
  final ModelSummary model;
  final List<MatchPrediction> forecasts;
  final List<MatchPrediction> recentBacktests;

  static List<MatchPrediction> _predictions(Object? value) {
    return (value as List<Object?>)
        .map(
          (item) =>
              MatchPrediction.fromJson((item as Map).cast<String, Object?>()),
        )
        .toList(growable: false);
  }
}

class ModelSummary {
  const ModelSummary({
    required this.selectedCandidate,
    required this.selectedCandidateLabel,
    required this.trainedThrough,
    required this.firstSeason,
    required this.lastSeason,
    required this.trainingMatches,
    required this.supportMatches,
    required this.supportName,
    required this.validationMatches,
    required this.holdoutMatches,
    required this.maeTotalCorners,
    required this.baselineMaeHoldout,
    required this.maeSkillVsDynamicPercent,
    required this.withinTwoHoldout,
    required this.brierOver9_5,
    required this.brierSkillOver9_5Percent,
    required this.calibrationErrorOver9_5,
    this.historicalDriftStatus = 'insufficient',
    this.recentMaeTotalCorners = 0,
    this.recentBrierOver9_5 = 0,
    this.driftReferenceMatches = 0,
    this.driftRecentMatches = 0,
    this.tradePolicyStatus = 'research-only',
    this.tradeEnabled = false,
    this.tradePolicyReason = '未有足夠固定時間真實角球盤快照；只顯示統計研究預測。',
  });

  factory ModelSummary.fromJson(Map<String, Object?> json) {
    final metrics = (json['metrics'] as Map).cast<String, Object?>();
    final drift = (json['drift'] as Map? ?? const {}).cast<String, Object?>();
    final tradePolicy = (json['tradePolicy'] as Map? ?? const {})
        .cast<String, Object?>();
    return ModelSummary(
      selectedCandidate: json['selectedCandidate'] as String,
      selectedCandidateLabel:
          json['selectedCandidateLabel'] as String? ??
          json['selectedCandidate'] as String,
      trainedThrough: json['trainedThrough'] as String,
      firstSeason: json['firstSeason'] as String,
      lastSeason: json['lastSeason'] as String,
      trainingMatches: (json['trainingMatches'] as num).toInt(),
      supportMatches: (json['supportMatches'] as num? ?? 0).toInt(),
      supportName: json['supportName'] as String? ?? '次級聯賽',
      validationMatches: (metrics['validationMatches'] as num).toInt(),
      holdoutMatches: (metrics['holdoutMatches'] as num? ?? 0).toInt(),
      maeTotalCorners: (metrics['maeTotalCorners'] as num).toDouble(),
      baselineMaeHoldout: (metrics['baselineMaeHoldout'] as num? ?? 0)
          .toDouble(),
      maeSkillVsDynamicPercent:
          (metrics['maeSkillVsDynamicPercent'] as num? ?? 0).toDouble(),
      withinTwoHoldout: (metrics['withinTwoHoldout'] as num? ?? 0).toDouble(),
      brierOver9_5: (metrics['brierOver9_5'] as num? ?? 0).toDouble(),
      brierSkillOver9_5Percent:
          (metrics['brierSkillOver9_5Percent'] as num? ?? 0).toDouble(),
      calibrationErrorOver9_5: (metrics['calibrationErrorOver9_5'] as num? ?? 0)
          .toDouble(),
      historicalDriftStatus: drift['status'] as String? ?? 'insufficient',
      recentMaeTotalCorners: (drift['recentMaeTotalCorners'] as num? ?? 0)
          .toDouble(),
      recentBrierOver9_5: (drift['recentBrierOver9_5'] as num? ?? 0).toDouble(),
      driftReferenceMatches: (drift['referenceMatches'] as num? ?? 0).toInt(),
      driftRecentMatches: (drift['recentMatches'] as num? ?? 0).toInt(),
      tradePolicyStatus: tradePolicy['status'] as String? ?? 'challenger-only',
      tradeEnabled: tradePolicy['tradeEnabled'] as bool? ?? false,
      tradePolicyReason:
          tradePolicy['reason'] as String? ?? '未有足夠固定時間真實角球盤快照；只顯示統計研究預測。',
    );
  }

  final String selectedCandidate;
  final String selectedCandidateLabel;
  final String trainedThrough;
  final String firstSeason;
  final String lastSeason;
  final int trainingMatches;
  final int supportMatches;
  final String supportName;
  final int validationMatches;
  final int holdoutMatches;
  final double maeTotalCorners;
  final double baselineMaeHoldout;
  final double maeSkillVsDynamicPercent;
  final double withinTwoHoldout;
  final double brierOver9_5;
  final double brierSkillOver9_5Percent;
  final double calibrationErrorOver9_5;
  final String historicalDriftStatus;
  final double recentMaeTotalCorners;
  final double recentBrierOver9_5;
  final int driftReferenceMatches;
  final int driftRecentMatches;
  final String tradePolicyStatus;
  final bool tradeEnabled;
  final String tradePolicyReason;
}

class MatchPrediction {
  const MatchPrediction({
    required this.matchId,
    required this.leagueCode,
    required this.leagueName,
    required this.mode,
    required this.date,
    required this.homeTeam,
    required this.awayTeam,
    this.homeTeamCn = '',
    this.awayTeamCn = '',
    required this.expectedHomeCorners,
    required this.expectedAwayCorners,
    required this.expectedTotalCorners,
    required this.actualTotalCorners,
    required this.interval80,
    required this.confidence,
    required this.confidenceScore,
    required this.markets,
    required this.totalDistribution,
    required this.factors,
    required this.recommendation,
    required this.forecastStage,
    required this.dataQuality,
    required this.modelStability,
    this.marketAvailable = false,
    this.marketSource = '',
    this.marketCapturedAt,
    this.marketLine,
    this.marketOverOdds,
    this.marketUnderOdds,
    this.conservativeProbability,
    this.minimumAcceptableOdds,
    this.researchDirection = '',
    this.tradeEligible = false,
    this.tradeReason = 'No bet：目前賽事沒有帶時間戳的實際角球盤，不能計算研究限價。',
  });

  factory MatchPrediction.fromJson(Map<String, Object?> json) {
    return MatchPrediction(
      matchId: json['matchId'] as String,
      leagueCode: json['leagueCode'] as String,
      leagueName: json['leagueName'] as String,
      mode: json['mode'] as String,
      date: DateTime.parse(json['date'] as String),
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      homeTeamCn: json['homeTeamCn'] as String? ?? '',
      awayTeamCn: json['awayTeamCn'] as String? ?? '',
      expectedHomeCorners: (json['expectedHomeCorners'] as num).toDouble(),
      expectedAwayCorners: (json['expectedAwayCorners'] as num).toDouble(),
      expectedTotalCorners: (json['expectedTotalCorners'] as num).toDouble(),
      actualTotalCorners: (json['actualTotalCorners'] as num?)?.toInt(),
      interval80: (json['interval80'] as List<Object?>)
          .map((value) => (value as num).toInt())
          .toList(growable: false),
      confidence: json['confidence'] as String? ?? 'backtest',
      confidenceScore: (json['confidenceScore'] as num? ?? 0).toDouble(),
      markets: (json['markets'] as List<Object?>)
          .map(
            (item) => MarketPrediction.fromJson(
              (item as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      totalDistribution: (json['totalDistribution'] as List<Object?>)
          .map((value) => (value as num).toDouble())
          .toList(growable: false),
      factors: (json['factors'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(growable: false),
      recommendation: json['recommendation'] as String? ?? 'model-view',
      forecastStage: json['forecastStage'] as String? ?? '歷史評估',
      dataQuality: (json['dataQuality'] as num? ?? 1).toDouble(),
      modelStability: (json['modelStability'] as num? ?? 0).toDouble(),
      marketAvailable: json['marketAvailable'] as bool? ?? false,
      marketSource: json['marketSource'] as String? ?? '',
      marketCapturedAt: json['marketCapturedAt'] == null
          ? null
          : DateTime.parse(json['marketCapturedAt'] as String),
      marketLine: (json['marketLine'] as num?)?.toDouble(),
      marketOverOdds: (json['marketOverOdds'] as num?)?.toDouble(),
      marketUnderOdds: (json['marketUnderOdds'] as num?)?.toDouble(),
      conservativeProbability: (json['conservativeProbability'] as num?)
          ?.toDouble(),
      minimumAcceptableOdds: (json['minimumAcceptableOdds'] as num?)
          ?.toDouble(),
      researchDirection: json['researchDirection'] as String? ?? '',
      tradeEligible: json['tradeEligible'] as bool? ?? false,
      tradeReason:
          json['tradeReason'] as String? ?? 'No bet：目前賽事沒有帶時間戳的實際角球盤，不能計算研究限價。',
    );
  }

  final String matchId;
  final String leagueCode;
  final String leagueName;
  final String mode;
  final DateTime date;
  final String homeTeam;
  final String awayTeam;
  final String homeTeamCn;
  final String awayTeamCn;
  final double expectedHomeCorners;
  final double expectedAwayCorners;
  final double expectedTotalCorners;
  final int? actualTotalCorners;
  final List<int> interval80;
  final String confidence;
  final double confidenceScore;
  final List<MarketPrediction> markets;
  final List<double> totalDistribution;
  final List<String> factors;
  final String recommendation;
  final String forecastStage;
  final double dataQuality;
  final double modelStability;
  final bool marketAvailable;
  final String marketSource;
  final DateTime? marketCapturedAt;
  final double? marketLine;
  final double? marketOverOdds;
  final double? marketUnderOdds;
  final double? conservativeProbability;
  final double? minimumAcceptableOdds;
  final String researchDirection;
  final bool tradeEligible;
  final String tradeReason;

  MarketPrediction get primaryMarket => markets.firstWhere(
    (market) => market.line == 9.5,
    orElse: () => markets.first,
  );

  OutcomeProbabilities probabilities({
    required String direction,
    required double line,
  }) {
    final roundedLine = (line * 4).round() / 4;
    final whole = roundedLine.floorToDouble();
    final fraction = roundedLine - whole;
    final componentLines = switch (fraction) {
      0.25 => [whole, whole + 0.5],
      0.75 => [whole + 0.5, whole + 1.0],
      _ => [roundedLine],
    };
    var win = 0.0;
    var push = 0.0;
    var loss = 0.0;
    for (final component in componentLines) {
      final outcome = _componentProbabilities(direction, component);
      win += outcome.win;
      push += outcome.push;
      loss += outcome.loss;
    }
    return OutcomeProbabilities(
      win: win / componentLines.length,
      push: push / componentLines.length,
      loss: loss / componentLines.length,
    );
  }

  OutcomeProbabilities _componentProbabilities(String direction, double line) {
    var win = 0.0;
    var push = 0.0;
    var loss = 0.0;
    for (var corners = 0; corners < totalDistribution.length; corners++) {
      final probability = totalDistribution[corners];
      final comparison = corners.compareTo(line);
      final isPush = line == line.roundToDouble() && comparison == 0;
      if (isPush) {
        push += probability;
      } else if (direction == 'over' ? comparison > 0 : comparison < 0) {
        win += probability;
      } else {
        loss += probability;
      }
    }
    return OutcomeProbabilities(win: win, push: push, loss: loss);
  }

  double expectedValue({
    required String direction,
    required double line,
    required double odds,
  }) {
    final outcome = probabilities(direction: direction, line: line);
    return outcome.win * (odds - 1) - outcome.loss;
  }
}

class OutcomeProbabilities {
  const OutcomeProbabilities({
    required this.win,
    required this.push,
    required this.loss,
  });

  final double win;
  final double push;
  final double loss;
}

class MarketPrediction {
  const MarketPrediction({
    required this.line,
    required this.overProbability,
    required this.underProbability,
    required this.fairOverOdds,
    required this.fairUnderOdds,
  });

  factory MarketPrediction.fromJson(Map<String, Object?> json) {
    return MarketPrediction(
      line: (json['line'] as num).toDouble(),
      overProbability: (json['overProbability'] as num).toDouble(),
      underProbability: (json['underProbability'] as num).toDouble(),
      fairOverOdds: (json['fairOverOdds'] as num).toDouble(),
      fairUnderOdds: (json['fairUnderOdds'] as num).toDouble(),
    );
  }

  final double line;
  final double overProbability;
  final double underProbability;
  final double fairOverOdds;
  final double fairUnderOdds;
}

class MatchResult {
  const MatchResult({required this.matchId, required this.actualTotalCorners});

  factory MatchResult.fromJson(Map<String, Object?> json) {
    return MatchResult(
      matchId: json['matchId'] as String,
      actualTotalCorners: (json['actualTotalCorners'] as num).toInt(),
    );
  }

  final String matchId;
  final int actualTotalCorners;
}

class RacingSummary {
  const RacingSummary({
    required this.available,
    required this.status,
    required this.sourceNotice,
    this.modelVersion = '',
    this.model = const RacingModelSummary(),
    this.races = const [],
    this.results = const [],
  });

  factory RacingSummary.fromJson(Map<String, Object?> json) {
    return RacingSummary(
      available: json['available'] as bool,
      status: json['status'] as String,
      sourceNotice: json['sourceNotice'] as String,
      modelVersion: json['modelVersion'] as String? ?? '',
      model: RacingModelSummary.fromJson(
        (json['model'] as Map? ?? const {}).cast<String, Object?>(),
      ),
      races: (json['races'] as List<Object?>? ?? const [])
          .map(
            (value) =>
                RacingRace.fromJson((value as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      results: (json['results'] as List<Object?>? ?? const [])
          .map(
            (value) =>
                RacingResult.fromJson((value as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
    );
  }

  final bool available;
  final String status;
  final String sourceNotice;
  final String modelVersion;
  final RacingModelSummary model;
  final List<RacingRace> races;
  final List<RacingResult> results;
}

class RacingModelSummary {
  const RacingModelSummary({
    this.selectedCandidate = '',
    this.trainingRaces = 0,
    this.holdoutRaces = 0,
    this.winLogLoss = 0,
    this.baselineWinLogLoss = 0,
    this.winLogLossSkillPercent = 0,
    this.winBrier = 0,
    this.placeBrier = 0,
    this.trainedThrough = '',
    this.firstSeason = '',
    this.lastSeason = '',
    this.trainingSeasons = 0,
    this.tradePolicyStatus = '',
    this.tradeEnabled = false,
    this.tradePolicyReason = '',
  });

  factory RacingModelSummary.fromJson(Map<String, Object?> json) {
    final tradePolicy = (json['tradePolicy'] as Map? ?? const {})
        .cast<String, Object?>();
    return RacingModelSummary(
      selectedCandidate: json['selectedCandidate'] as String? ?? '',
      trainingRaces: (json['trainingRaces'] as num? ?? 0).toInt(),
      holdoutRaces: (json['holdoutRaces'] as num? ?? 0).toInt(),
      winLogLoss: (json['winLogLoss'] as num? ?? 0).toDouble(),
      baselineWinLogLoss: (json['baselineWinLogLoss'] as num? ?? 0).toDouble(),
      winLogLossSkillPercent: (json['winLogLossSkillPercent'] as num? ?? 0)
          .toDouble(),
      winBrier: (json['winBrier'] as num? ?? 0).toDouble(),
      placeBrier: (json['placeBrier'] as num? ?? 0).toDouble(),
      trainedThrough: json['trainedThrough'] as String? ?? '',
      firstSeason: json['firstSeason'] as String? ?? '',
      lastSeason: json['lastSeason'] as String? ?? '',
      trainingSeasons: (json['trainingSeasons'] as num? ?? 0).toInt(),
      tradePolicyStatus: tradePolicy['status'] as String? ?? '',
      tradeEnabled: tradePolicy['tradeEnabled'] as bool? ?? false,
      tradePolicyReason: tradePolicy['reason'] as String? ?? '',
    );
  }

  final String selectedCandidate;
  final int trainingRaces;
  final int holdoutRaces;
  final double winLogLoss;
  final double baselineWinLogLoss;
  final double winLogLossSkillPercent;
  final double winBrier;
  final double placeBrier;
  final String trainedThrough;
  final String firstSeason;
  final String lastSeason;
  final int trainingSeasons;
  final String tradePolicyStatus;
  final bool tradeEnabled;
  final String tradePolicyReason;

  String get candidateLabel => switch (selectedCandidate) {
    'boosting' => '排名提升模型',
    'mobile_logistic' => 'Mobile Logistic Ranking Model',
    'mobile_dynamic' => '手機動態往績基準',
    _ => '動態往績基準',
  };
}

class RacingRace {
  const RacingRace({
    required this.raceId,
    required this.date,
    required this.startTime,
    required this.venue,
    required this.raceNumber,
    required this.raceName,
    required this.distanceMetres,
    required this.surface,
    required this.course,
    required this.going,
    required this.raceClass,
    required this.runners,
  });

  factory RacingRace.fromJson(Map<String, Object?> json) {
    return RacingRace(
      raceId: json['raceId'] as String,
      date: DateTime.parse(json['date'] as String),
      startTime: DateTime.parse(
        json['startTime'] as String? ?? '${json['date']}T00:00:00+08:00',
      ),
      venue: json['venue'] as String,
      raceNumber: (json['raceNumber'] as num).toInt(),
      raceName: json['raceName'] as String? ?? '',
      distanceMetres: (json['distanceMetres'] as num).toInt(),
      surface: json['surface'] as String,
      course: json['course'] as String? ?? '',
      going: json['going'] as String? ?? '',
      raceClass: json['raceClass'] as String? ?? '',
      runners: (json['runners'] as List<Object?>)
          .map(
            (value) =>
                RacingRunner.fromJson((value as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
    );
  }

  final String raceId;
  final DateTime date;
  final DateTime startTime;
  final String venue;
  final int raceNumber;
  final String raceName;
  final int distanceMetres;
  final String surface;
  final String course;
  final String going;
  final String raceClass;
  final List<RacingRunner> runners;
}

class RacingRunner {
  const RacingRunner({
    required this.horseId,
    required this.horseName,
    this.horseNameEnglish = '',
    this.horseNameChinese = '',
    required this.number,
    required this.draw,
    required this.jockey,
    required this.trainer,
    required this.winProbability,
    required this.placeProbability,
    required this.fairWinOdds,
    required this.fairPlaceOdds,
    required this.confidence,
    required this.confidenceScore,
    required this.recommendation,
    required this.factors,
  });

  factory RacingRunner.fromJson(Map<String, Object?> json) {
    return RacingRunner(
      horseId: json['horseId'] as String,
      horseName: json['horseName'] as String,
      horseNameEnglish:
          json['horseNameEnglish'] as String? ?? json['horseName'] as String,
      horseNameChinese: json['horseNameChinese'] as String? ?? '',
      number: (json['number'] as num).toInt(),
      draw: (json['draw'] as num).toInt(),
      jockey: json['jockey'] as String,
      trainer: json['trainer'] as String,
      winProbability: (json['winProbability'] as num).toDouble(),
      placeProbability: (json['placeProbability'] as num).toDouble(),
      fairWinOdds: (json['fairWinOdds'] as num).toDouble(),
      fairPlaceOdds: (json['fairPlaceOdds'] as num? ?? 0).toDouble(),
      confidence: json['confidence'] as String,
      confidenceScore: (json['confidenceScore'] as num).toDouble(),
      recommendation: json['recommendation'] as String? ?? 'model-view',
      factors: (json['factors'] as List<Object?>? ?? const [])
          .map((value) => value as String)
          .toList(growable: false),
    );
  }

  final String horseId;
  final String horseName;
  final String horseNameEnglish;
  final String horseNameChinese;
  final int number;
  final int draw;
  final String jockey;
  final String trainer;
  final double winProbability;
  final double placeProbability;
  final double fairWinOdds;
  final double fairPlaceOdds;
  final String confidence;
  final double confidenceScore;
  final String recommendation;
  final List<String> factors;
}

class RacingResult {
  const RacingResult({
    required this.raceId,
    required this.horseId,
    required this.finishPosition,
  });

  factory RacingResult.fromJson(Map<String, Object?> json) {
    return RacingResult(
      raceId: json['raceId'] as String,
      horseId: json['horseId'] as String,
      finishPosition: (json['finishPosition'] as num).toInt(),
    );
  }

  final String raceId;
  final String horseId;
  final int finishPosition;
}
