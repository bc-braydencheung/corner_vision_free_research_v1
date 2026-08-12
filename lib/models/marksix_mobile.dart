/// Mark Six mobile data models for EdgeWise app.

class MarkSixPrize {
  const MarkSixPrize({
    required this.name,
    this.nameEn = '',
    this.requirement = '',
    this.prizePerUnit = 0,
    this.winningUnits = 0,
  });

  factory MarkSixPrize.fromJson(Map<String, Object?> json) {
    // Handle GraphQL scraper format (type, winningUnit, dividend)
    if (json.containsKey('type') && !json.containsKey('name')) {
      final type = (json['type'] as num?)?.toInt() ?? 0;
      final names = ['', '頭獎', '二獎', '三獎', '四獎', '五獎', '六獎', '七獎'];
      return MarkSixPrize(
        name: type < names.length ? names[type] : '獎項$type',
        prizePerUnit: double.tryParse((json['dividend'] ?? '').toString()) ?? 0,
        winningUnits: double.tryParse((json['winningUnit'] ?? '').toString()) ?? 0,
      );
    }
    // Existing format
    return MarkSixPrize(
      name: json['name'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      requirement: json['requirement'] as String? ?? '',
      prizePerUnit: (json['prizePerUnit'] as num?)?.toDouble() ?? 0,
      winningUnits: (json['winningUnits'] as num?)?.toDouble() ?? 0,
    );
  }

  final String name;
  final String nameEn;
  final String requirement;
  final double prizePerUnit;
  final double winningUnits;

  Map<String, Object?> toJson() => {
    'name': name, 'nameEn': nameEn, 'requirement': requirement,
    'prizePerUnit': prizePerUnit, 'winningUnits': winningUnits,
  };
}

class MarkSixDraw {
  const MarkSixDraw({
    required this.drawNumber,
    required this.drawDate,
    required this.numbers,
    this.specialNumber = 0,
    this.totalTurnover = 0,
    this.prizes = const [],
    this.source = '',
  });

  factory MarkSixDraw.fromJson(Map<String, Object?> json) {
    // Handle GraphQL scraper format
    if (json.containsKey('drawResult') && !json.containsKey('numbers')) {
      final dr = (json['drawResult'] as Map<String, Object?>?) ?? {};
      final drawnNo = (dr['drawnNo'] as List<Object?>?)?.map((n) => int.parse(n.toString())).toList() ?? [];
      final xDrawnNo = int.tryParse((dr['xDrawnNo'] ?? '').toString()) ?? 0;
      final lp = (json['lotteryPool'] as Map<String, Object?>?) ?? {};
      final prizes = (lp['lotteryPrizes'] as List<Object?>?)
          ?.map((p) => MarkSixPrize.fromJson((p as Map).cast<String, Object?>()))
          .toList() ?? const [];
      return MarkSixDraw(
        drawNumber: (json['id'] as String?) ?? '',
        drawDate: ((json['drawDate'] as String?) ?? '').split('+').first,
        numbers: drawnNo,
        specialNumber: xDrawnNo,
        totalTurnover: double.tryParse((lp['totalInvestment'] ?? '').toString()) ?? 0,
        prizes: prizes,
        source: 'graphql',
      );
    }
    // Handle existing app format
    return MarkSixDraw(
      drawNumber: json['drawNumber'] as String? ?? '',
      drawDate: json['drawDate'] as String? ?? '',
      numbers: (json['numbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? [],
      specialNumber: (json['specialNumber'] as num?)?.toInt() ?? 0,
      totalTurnover: (json['totalTurnover'] as num?)?.toDouble() ?? 0,
      prizes: (json['prizes'] as List<Object?>?)
          ?.map((p) => MarkSixPrize.fromJson((p as Map).cast<String, Object?>()))
          .toList() ?? const [],
      source: json['source'] as String? ?? '',
    );
  }

  final String drawNumber;
  final String drawDate;
  final List<int> numbers;
  final int specialNumber;
  final double totalTurnover;
  final List<MarkSixPrize> prizes;
  final String source;

  Map<String, Object?> toJson() => {
    'drawNumber': drawNumber, 'drawDate': drawDate,
    'numbers': numbers, 'specialNumber': specialNumber,
    'totalTurnover': totalTurnover,
    'prizes': prizes.map((p) => p.toJson()).toList(),
    'source': source,
  };
}



class MarkSixSeedData {
  const MarkSixSeedData({
    this.schemaVersion = '', this.generatedAt = '',
    this.sourceUrl = '', this.sourceNotice = '',
    this.totalDraws = 0, this.draws = const [],
  });

  factory MarkSixSeedData.fromJson(Map<String, Object?> json) {
    return MarkSixSeedData(
      schemaVersion: json['schemaVersion'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      sourceNotice: json['sourceNotice'] as String? ?? '',
      totalDraws: (json['totalDraws'] as num?)?.toInt() ?? 0,
      draws: (json['draws'] as List<Object?>?)
          ?.map((d) => MarkSixDraw.fromJson((d as Map).cast<String, Object?>()))
          .toList() ?? const [],
    );
  }

  final String schemaVersion;
  final String generatedAt;
  final String sourceUrl;
  final String sourceNotice;
  final int totalDraws;
  final List<MarkSixDraw> draws;

  MarkSixSeedData withDraws(List<MarkSixDraw> value) => MarkSixSeedData(
    schemaVersion: schemaVersion, generatedAt: generatedAt,
    sourceUrl: sourceUrl, sourceNotice: sourceNotice,
    totalDraws: value.length, draws: value,
  );
}

class MarkSixStats {
  const MarkSixStats({
    this.totalDraws = 0, this.dateRange = '',
    this.hotNumbers = const [], this.coldNumbers = const [],
    this.numberFrequency = const {},
    this.oddEvenRatio = 0, this.avgSum = 0,
    this.consecutiveRate = 0, this.topPrizeAvg = 0, this.avgTurnover = 0,
  });

  factory MarkSixStats.fromJson(Map<String, Object?> json) {
    return MarkSixStats(
      totalDraws: (json['totalDraws'] as num?)?.toInt() ?? 0,
      dateRange: json['dateRange'] as String? ?? '',
      hotNumbers: (json['hotNumbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? const [],
      coldNumbers: (json['coldNumbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? const [],
      numberFrequency: (json['numberFrequency'] as Map<String, Object?>?)
          ?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? const {},
      oddEvenRatio: (json['oddEvenRatio'] as num?)?.toDouble() ?? 0,
      avgSum: (json['avgSum'] as num?)?.toDouble() ?? 0,
      consecutiveRate: (json['consecutiveRate'] as num?)?.toDouble() ?? 0,
      topPrizeAvg: (json['topPrizeAvg'] as num?)?.toDouble() ?? 0,
      avgTurnover: (json['avgTurnover'] as num?)?.toDouble() ?? 0,
    );
  }

  final int totalDraws;
  final String dateRange;
  final List<int> hotNumbers;
  final List<int> coldNumbers;
  final Map<String, int> numberFrequency;
  final double oddEvenRatio;
  final double avgSum;
  final double consecutiveRate;
  final double topPrizeAvg;
  final double avgTurnover;

  Map<String, Object?> toJson() => {
    'totalDraws': totalDraws, 'dateRange': dateRange,
    'hotNumbers': hotNumbers, 'coldNumbers': coldNumbers,
    'numberFrequency': numberFrequency.map((k, v) => MapEntry(k, v)),
    'oddEvenRatio': oddEvenRatio, 'avgSum': avgSum,
    'consecutiveRate': consecutiveRate,
    'topPrizeAvg': topPrizeAvg, 'avgTurnover': avgTurnover,
  };
}



class MarkSixPrediction {
  const MarkSixPrediction({
    this.recommendedNumbers = const [], this.specialNumber = 0,
    this.confidence = 0, this.confidenceLabel = 'low',
    this.modelVersion = '', this.generatedAt = '',
    this.individualProbabilities = const {}, this.factors = const [],
    this.numberReasoning = const {},
    this.patternNumbers = const [], this.patternSpecial = 0,
    this.patternReasoning = const {},
  });

  factory MarkSixPrediction.fromJson(Map<String, Object?> json) {
    return MarkSixPrediction(
      recommendedNumbers: (json['recommendedNumbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? const [],
      specialNumber: (json['specialNumber'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      confidenceLabel: json['confidenceLabel'] as String? ?? 'low',
      modelVersion: json['modelVersion'] as String? ?? '',
      generatedAt: json['generatedAt'] as String? ?? '',
      individualProbabilities: (json['individualProbabilities'] as Map<String, Object?>?)
          ?.map((k, v) => MapEntry(int.parse(k), (v as num).toDouble())) ?? const {},
      factors: (json['factors'] as List<Object?>?)
          ?.map((f) => f as String).toList() ?? const [],
      numberReasoning: (json['numberReasoning'] as Map<String, Object?>?)
          ?.map((k, v) => MapEntry(int.parse(k), (v as Map).cast<String, Object?>())) ?? const {},
      patternNumbers: (json['patternNumbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? const [],
      patternSpecial: (json['patternSpecial'] as num?)?.toInt() ?? 0,
      patternReasoning: (json['patternReasoning'] as Map<String, Object?>?)
          ?.cast<String, Object?>() ?? const {},
    );
  }

  final List<int> recommendedNumbers;
  final int specialNumber;
  final double confidence;
  final String confidenceLabel;
  final String modelVersion;
  final String generatedAt;
  final Map<int, double> individualProbabilities;
  final List<String> factors;
  final Map<int, Map<String, Object?>> numberReasoning;
  final List<int> patternNumbers;
  final int patternSpecial;
  final Map<String, Object?> patternReasoning;
}

class MarkSixCorrection {
  const MarkSixCorrection({
    required this.drawDate, required this.predictedNumbers,
    required this.actualNumbers, required this.matches,
    this.frequencyModelWeight = 0.33, this.markovModelWeight = 0.33,
    this.mlModelWeight = 0.33, this.rollingAccuracy = 0,
  });

  factory MarkSixCorrection.fromJson(Map<String, Object?> json) {
    return MarkSixCorrection(
      drawDate: json['drawDate'] as String? ?? '',
      predictedNumbers: (json['predictedNumbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? const [],
      actualNumbers: (json['actualNumbers'] as List<Object?>?)
          ?.map((n) => (n as num).toInt()).toList() ?? const [],
      matches: (json['matches'] as num?)?.toInt() ?? 0,
      frequencyModelWeight: (json['frequencyModelWeight'] as num?)?.toDouble() ?? 0.33,
      markovModelWeight: (json['markovModelWeight'] as num?)?.toDouble() ?? 0.33,
      mlModelWeight: (json['mlModelWeight'] as num?)?.toDouble() ?? 0.33,
      rollingAccuracy: (json['rollingAccuracy'] as num?)?.toDouble() ?? 0,
    );
  }

  final String drawDate;
  final List<int> predictedNumbers;
  final List<int> actualNumbers;
  final int matches;
  final double frequencyModelWeight;
  final double markovModelWeight;
  final double mlModelWeight;
  final double rollingAccuracy;

  Map<String, Object?> toJson() => {
    'drawDate': drawDate, 'predictedNumbers': predictedNumbers,
    'actualNumbers': actualNumbers, 'matches': matches,
    'frequencyModelWeight': frequencyModelWeight,
    'markovModelWeight': markovModelWeight,
    'mlModelWeight': mlModelWeight, 'rollingAccuracy': rollingAccuracy,
  };
}
