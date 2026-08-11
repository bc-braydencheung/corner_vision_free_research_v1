class SimulatedTrade {
  const SimulatedTrade({
    required this.id,
    required this.matchId,
    required this.leagueCode,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.matchDate,
    required this.createdAt,
    required this.direction,
    required this.line,
    required this.odds,
    required this.stake,
    required this.modelWinProbability,
    required this.modelPushProbability,
    required this.expectedValue,
    required this.confidence,
    required this.status,
    required this.actualTotalCorners,
    required this.profit,
    this.sport = 'football',
    this.marketType = 'corners',
    this.selectionId,
    this.finishPosition,
    this.placeSlots,
    this.modelVersion,
    this.stakeStrategy = 'legacy',
    this.marketSource = '',
    this.marketCapturedAt,
    this.minimumAcceptableOdds,
  });

  factory SimulatedTrade.fromJson(Map<String, Object?> json) {
    return SimulatedTrade(
      id: json['id'] as String,
      matchId: json['matchId'] as String,
      leagueCode: json['leagueCode'] as String,
      leagueName: json['leagueName'] as String,
      homeTeam: json['homeTeam'] as String,
      awayTeam: json['awayTeam'] as String,
      matchDate: DateTime.parse(json['matchDate'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      direction: json['direction'] as String,
      line: (json['line'] as num).toDouble(),
      odds: (json['odds'] as num).toDouble(),
      stake: (json['stake'] as num).toDouble(),
      modelWinProbability: (json['modelWinProbability'] as num).toDouble(),
      modelPushProbability: (json['modelPushProbability'] as num).toDouble(),
      expectedValue: (json['expectedValue'] as num).toDouble(),
      confidence: json['confidence'] as String,
      status: json['status'] as String,
      actualTotalCorners: (json['actualTotalCorners'] as num?)?.toInt(),
      profit: (json['profit'] as num?)?.toDouble(),
      sport: json['sport'] as String? ?? 'football',
      marketType: json['marketType'] as String? ?? 'corners',
      selectionId: json['selectionId'] as String?,
      finishPosition: (json['finishPosition'] as num?)?.toInt(),
      placeSlots: (json['placeSlots'] as num?)?.toInt(),
      modelVersion: json['modelVersion'] as String?,
      stakeStrategy: json['stakeStrategy'] as String? ?? 'legacy',
      marketSource: json['marketSource'] as String? ?? '',
      marketCapturedAt: json['marketCapturedAt'] == null
          ? null
          : DateTime.parse(json['marketCapturedAt'] as String),
      minimumAcceptableOdds: (json['minimumAcceptableOdds'] as num?)
          ?.toDouble(),
    );
  }

  final String id;
  final String matchId;
  final String leagueCode;
  final String leagueName;
  final String homeTeam;
  final String awayTeam;
  final DateTime matchDate;
  final DateTime createdAt;
  final String direction;
  final double line;
  final double odds;
  final double stake;
  final double modelWinProbability;
  final double modelPushProbability;
  final double expectedValue;
  final String confidence;
  final String status;
  final int? actualTotalCorners;
  final double? profit;
  final String sport;
  final String marketType;
  final String? selectionId;
  final int? finishPosition;
  final int? placeSlots;
  final String? modelVersion;
  final String stakeStrategy;
  final String marketSource;
  final DateTime? marketCapturedAt;
  final double? minimumAcceptableOdds;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'matchId': matchId,
      'leagueCode': leagueCode,
      'leagueName': leagueName,
      'homeTeam': homeTeam,
      'awayTeam': awayTeam,
      'matchDate': matchDate.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'direction': direction,
      'line': line,
      'odds': odds,
      'stake': stake,
      'modelWinProbability': modelWinProbability,
      'modelPushProbability': modelPushProbability,
      'expectedValue': expectedValue,
      'confidence': confidence,
      'status': status,
      'actualTotalCorners': actualTotalCorners,
      'profit': profit,
      'sport': sport,
      'marketType': marketType,
      'selectionId': selectionId,
      'finishPosition': finishPosition,
      'placeSlots': placeSlots,
      'modelVersion': modelVersion,
      'stakeStrategy': stakeStrategy,
      'marketSource': marketSource,
      'marketCapturedAt': marketCapturedAt?.toUtc().toIso8601String(),
      'minimumAcceptableOdds': minimumAcceptableOdds,
    };
  }

  SimulatedTrade settle({required int totalCorners}) {
    return SimulatedTrade(
      id: id,
      matchId: matchId,
      leagueCode: leagueCode,
      leagueName: leagueName,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      matchDate: matchDate,
      createdAt: createdAt,
      direction: direction,
      line: line,
      odds: odds,
      stake: stake,
      modelWinProbability: modelWinProbability,
      modelPushProbability: modelPushProbability,
      expectedValue: expectedValue,
      confidence: confidence,
      status: 'settled',
      actualTotalCorners: totalCorners,
      profit: stake * _returnPerUnit(totalCorners),
      sport: sport,
      marketType: marketType,
      selectionId: selectionId,
      finishPosition: finishPosition,
      placeSlots: placeSlots,
      modelVersion: modelVersion,
      stakeStrategy: stakeStrategy,
      marketSource: marketSource,
      marketCapturedAt: marketCapturedAt,
      minimumAcceptableOdds: minimumAcceptableOdds,
    );
  }

  SimulatedTrade settleRacing({required int position}) {
    return SimulatedTrade(
      id: id,
      matchId: matchId,
      leagueCode: leagueCode,
      leagueName: leagueName,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      matchDate: matchDate,
      createdAt: createdAt,
      direction: direction,
      line: line,
      odds: odds,
      stake: stake,
      modelWinProbability: modelWinProbability,
      modelPushProbability: modelPushProbability,
      expectedValue: expectedValue,
      confidence: confidence,
      status: 'settled',
      actualTotalCorners: null,
      profit:
          stake *
          (marketType == 'place'
              ? position <= (placeSlots ?? 3)
                    ? odds - 1
                    : -1
              : position == 1
              ? odds - 1
              : -1),
      sport: sport,
      marketType: marketType,
      selectionId: selectionId,
      finishPosition: position,
      placeSlots: placeSlots,
      modelVersion: modelVersion,
      stakeStrategy: stakeStrategy,
      marketSource: marketSource,
      marketCapturedAt: marketCapturedAt,
      minimumAcceptableOdds: minimumAcceptableOdds,
    );
  }

  double _returnPerUnit(int totalCorners) {
    final roundedLine = (line * 4).round() / 4;
    final whole = roundedLine.floorToDouble();
    final fraction = roundedLine - whole;
    final componentLines = switch (fraction) {
      0.25 => [whole, whole + 0.5],
      0.75 => [whole + 0.5, whole + 1.0],
      _ => [roundedLine],
    };
    var result = 0.0;
    for (final component in componentLines) {
      if (component == totalCorners) {
        continue;
      }
      final won = direction == 'over'
          ? totalCorners > component
          : totalCorners < component;
      result += won ? odds - 1 : -1;
    }
    return result / componentLines.length;
  }
}
