import 'dart:math';

import '../models/football_mobile.dart';
import '../models/forecast_data.dart';

class FootballMobileEngine {
  static const featureCount = 22;

  List<FootballTrainingRow> buildTrainingRows(
    MobileFootballDataset dataset,
    FootballLeagueConfig league,
  ) {
    final state = _FootballFeatureState(league);
    final output = <FootballTrainingRow>[];
    final rows = List<FootballMatchRecord>.from(dataset.rows)
      ..sort(_compareMatches);
    final relevant = rows
        .where(
          (row) =>
              row.division == league.code || row.division == league.supportCode,
        )
        .toList();
    var index = 0;
    while (index < relevant.length) {
      final date = relevant[index].date;
      final sameDate = <FootballMatchRecord>[];
      while (index < relevant.length && relevant[index].date == date) {
        sameDate.add(relevant[index]);
        index++;
      }
      for (final row in sameDate.where((row) => row.division == league.code)) {
        final built = state.features(row);
        output.add(
          FootballTrainingRow(
            matchId: row.matchId,
            date: row.date,
            features: built.values,
            homeCorners: row.homeCorners!,
            awayCorners: row.awayCorners!,
            baselineHome: built.baselineHome,
            baselineAway: built.baselineAway,
          ),
        );
      }
      for (final row in sameDate) {
        state.update(row);
      }
    }
    return output;
  }

  List<LeagueForecastData> predictLeagues({
    required List<LeagueForecastData> bundled,
    required MobileFootballDataset dataset,
    MobileFootballModel? model,
  }) {
    final modelByCode = {
      for (final league
          in model?.leagues ?? const <MobileFootballLeagueModel>[])
        league.code: league,
    };
    return [
      for (final league in bundled)
        _predictLeague(
          bundled: league,
          dataset: dataset,
          model: modelByCode[league.code],
          modelTrainedThrough: model?.trainedThrough[league.code],
        ),
    ];
  }

  LeagueForecastData _predictLeague({
    required LeagueForecastData bundled,
    required MobileFootballDataset dataset,
    required MobileFootballLeagueModel? model,
    required String? modelTrainedThrough,
  }) {
    final config = dataset.leagues.firstWhere(
      (league) => league.code == bundled.code,
    );
    final state = _FootballFeatureState(config);
    final relevant =
        dataset.rows
            .where(
              (row) =>
                  row.division == config.code ||
                  row.division == config.supportCode,
            )
            .toList()
          ..sort(_compareMatches);
    for (final row in relevant) {
      state.update(row);
    }
    final fixtures =
        dataset.fixtures
            .where((fixture) => fixture.division == config.code)
            .toList()
          ..sort(_compareMatches);
    final forecasts = [
      for (final fixture in fixtures)
        _prediction(fixture, state.features(fixture), config, model),
    ];
    final modelSummary = forecasts.isEmpty
        ? bundled.model
        : ModelSummary(
            selectedCandidate: model?.useModel == true
                ? 'mobile_poisson'
                : 'mobile_dynamic',
            selectedCandidateLabel: model?.useModel == true
                ? 'Mobile Recency-Weighted Count Model'
                : 'Mobile Dynamic Baseline',
            trainedThrough:
                modelTrainedThrough ?? dataset.trainedThrough(config.code),
            firstSeason: bundled.model.firstSeason,
            lastSeason: bundled.model.lastSeason,
            trainingMatches:
                model?.trainingMatches ??
                relevant.where((row) => row.division == config.code).length,
            supportMatches: relevant
                .where((row) => row.division == config.supportCode)
                .length,
            supportName: config.supportName,
            validationMatches: bundled.model.validationMatches,
            holdoutMatches:
                model?.holdoutMatches ?? bundled.model.holdoutMatches,
            maeTotalCorners: model?.mae ?? bundled.model.baselineMaeHoldout,
            baselineMaeHoldout:
                model?.baselineMae ?? bundled.model.baselineMaeHoldout,
            maeSkillVsDynamicPercent: model == null || model.baselineMae <= 0
                ? 0
                : (model.baselineMae - model.mae) / model.baselineMae * 100,
            withinTwoHoldout: bundled.model.withinTwoHoldout,
            brierOver9_5: model?.brierOver95 ?? bundled.model.brierOver9_5,
            brierSkillOver9_5Percent:
                model == null || model.baselineBrierOver95 <= 0
                ? 0
                : (model.baselineBrierOver95 - model.brierOver95) /
                      model.baselineBrierOver95 *
                      100,
            calibrationErrorOver9_5: bundled.model.calibrationErrorOver9_5,
            historicalDriftStatus: bundled.model.historicalDriftStatus,
            recentMaeTotalCorners: bundled.model.recentMaeTotalCorners,
            recentBrierOver9_5: bundled.model.recentBrierOver9_5,
            driftReferenceMatches: bundled.model.driftReferenceMatches,
            driftRecentMatches: bundled.model.driftRecentMatches,
            tradePolicyStatus: bundled.model.tradePolicyStatus,
            tradeEnabled: bundled.model.tradeEnabled,
            tradePolicyReason: bundled.model.tradePolicyReason,
          );
    return LeagueForecastData(
      code: bundled.code,
      name: bundled.name,
      supportName: bundled.supportName,
      status: forecasts.isEmpty
          ? '目前來源尚未發布未來賽程'
          : '手機已根據最新資料預測 ${forecasts.length} 場未來賽事',
      model: modelSummary,
      forecasts: forecasts,
      recentBacktests: bundled.recentBacktests,
    );
  }

  MatchPrediction _prediction(
    FootballMatchRecord fixture,
    _BuiltFootballFeatures built,
    FootballLeagueConfig league,
    MobileFootballLeagueModel? model,
  ) {
    var home = built.baselineHome;
    var away = built.baselineAway;
    if (model?.useModel ?? false) {
      final normalised = _normalise(
        built.values,
        model!.featureMeans,
        model.featureScales,
      );
      home = _countPrediction(
        model.homeWeights,
        model.homeIntercept,
        normalised,
      );
      away = _countPrediction(
        model.awayWeights,
        model.awayIntercept,
        normalised,
      );
      final total = _countPrediction(
        model.totalWeights,
        model.totalIntercept,
        normalised,
      );
      final scale = total / max(home + away, 0.1);
      home = (home * scale).clamp(0.2, 18);
      away = (away * scale).clamp(0.2, 18);
    }
    final expectedTotal = home + away;
    final distribution = poissonDistribution(expectedTotal);
    final over = distribution.skip(10).fold(0.0, (sum, value) => sum + value);
    final edge = (over - 0.5).abs();
    final experience = min(built.values[16], built.values[17]);
    final dataQuality = (0.55 + min(experience / 3, 0.45)).clamp(0.4, 1.0);
    final stability = model?.useModel == true ? 0.7 : 0.52;
    final confidenceScore =
        (0.45 * dataQuality + 0.35 * stability + 0.2 * min(edge / 0.15, 1))
            .clamp(0.0, 1.0);
    final confidence = edge < 0.055 || confidenceScore < 0.52
        ? 'avoid'
        : confidenceScore >= 0.78 && edge >= 0.14
        ? 'high'
        : confidenceScore >= 0.63 && edge >= 0.09
        ? 'medium'
        : 'low';
    final interval = _interval(distribution);
    return MatchPrediction(
      matchId: fixture.matchId,
      leagueCode: league.code,
      leagueName: league.name,
      mode: 'forecast',
      date: DateTime.parse(fixture.date),
      homeTeam: fixture.homeTeam,
      awayTeam: fixture.awayTeam,
      expectedHomeCorners: home,
      expectedAwayCorners: away,
      expectedTotalCorners: expectedTotal,
      actualTotalCorners: null,
      interval80: interval,
      confidence: confidence,
      confidenceScore: confidenceScore,
      markets: _markets(distribution),
      totalDistribution: distribution,
      factors: _factors(built, league.supportName),
      recommendation: confidence == 'avoid' ? 'no-prediction' : 'model-view',
      forecastStage: '手機最新資料',
      dataQuality: dataQuality,
      modelStability: stability,
    );
  }

  static List<double> poissonDistribution(double mean, {int maxCount = 30}) {
    final probabilities = List<double>.filled(maxCount + 1, 0);
    probabilities[0] = exp(-mean.clamp(0.1, 30));
    var assigned = probabilities[0];
    for (var count = 1; count < maxCount; count++) {
      probabilities[count] = probabilities[count - 1] * mean / count;
      assigned += probabilities[count];
    }
    probabilities[maxCount] = max(1 - assigned, 0);
    final total = probabilities.fold(0.0, (sum, value) => sum + value);
    return probabilities.map((value) => value / total).toList(growable: false);
  }

  static double over95Probability(double mean) =>
      poissonDistribution(mean).skip(10).fold(0.0, (sum, value) => sum + value);

  static double _countPrediction(
    List<double> weights,
    double intercept,
    List<double> features,
  ) {
    var value = intercept;
    for (var index = 0; index < weights.length; index++) {
      value += weights[index] * features[index];
    }
    return (exp(value.clamp(-2.0, 3.5)) - 0.5).clamp(0.1, 20);
  }

  static List<double> _normalise(
    List<double> values,
    List<double> means,
    List<double> scales,
  ) => [
    for (var index = 0; index < values.length; index++)
      (values[index] - means[index]) / max(scales[index], 0.0001),
  ];

  static List<int> _interval(List<double> distribution) {
    var cumulative = 0.0;
    var lower = 0;
    var upper = distribution.length - 1;
    for (var index = 0; index < distribution.length; index++) {
      cumulative += distribution[index];
      if (cumulative >= 0.1 && lower == 0) {
        lower = index;
      }
      if (cumulative >= 0.9) {
        upper = index;
        break;
      }
    }
    return [lower, max(upper, lower + 1)];
  }

  static List<MarketPrediction> _markets(List<double> distribution) => [
    for (final line in const [7.5, 8.5, 9.5, 10.5, 11.5, 12.5])
      _market(distribution, line),
  ];

  static MarketPrediction _market(List<double> distribution, double line) {
    final over = distribution
        .skip(line.floor() + 1)
        .fold(0.0, (sum, value) => sum + value);
    return MarketPrediction(
      line: line,
      overProbability: over,
      underProbability: 1 - over,
      fairOverOdds: 1 / max(over, 0.01),
      fairUnderOdds: 1 / max(1 - over, 0.01),
    );
  }

  static List<String> _factors(
    _BuiltFootballFeatures built,
    String supportName,
  ) {
    final output = <String>[];
    final recentAttack = built.values[4] + built.values[6];
    final leagueTotal = built.values[2] + built.values[3];
    if (recentAttack > leagueTotal + 0.8) {
      output.add('兩隊近期製造角球高於聯賽基準');
    } else if (recentAttack < leagueTotal - 0.8) {
      output.add('兩隊近期製造角球低於聯賽基準');
    }
    if ((built.values[20] - 0.5).abs() > 0.08) {
      output.add('入球市場反映比賽節奏偏離平均');
    }
    if (min(built.values[16], built.values[17]) < 0.7) {
      output.add('球隊樣本較少，已使用$supportName折算先驗');
    }
    if (output.isEmpty) {
      output.add('近期角球走勢接近聯賽平均');
    }
    return output.take(3).toList(growable: false);
  }

  static int _compareMatches(
    FootballMatchRecord left,
    FootballMatchRecord right,
  ) {
    final date = left.date.compareTo(right.date);
    return date != 0 ? date : left.matchId.compareTo(right.matchId);
  }
}

class _FootballFeatureState {
  _FootballFeatureState(this.league);

  final FootballLeagueConfig league;
  final Map<String, _TeamState> teams = {};
  final List<double> leagueHomeCorners = [];
  final List<double> leagueAwayCorners = [];

  _BuiltFootballFeatures features(FootballMatchRecord row) {
    final home = teams.putIfAbsent(row.homeTeam, _TeamState.new);
    final away = teams.putIfAbsent(row.awayTeam, _TeamState.new);
    final leagueHome = _tailMean(leagueHomeCorners, 100, 5.5);
    final leagueAway = _tailMean(leagueAwayCorners, 100, 4.8);
    final defaultTeam = (leagueHome + leagueAway) / 2;
    final homeAttack = home.mean('cornersFor', 20, defaultTeam);
    final homeDefence = home.mean('cornersAgainst', 20, defaultTeam);
    final awayAttack = away.mean('cornersFor', 20, defaultTeam);
    final awayDefence = away.mean('cornersAgainst', 20, defaultTeam);
    final homeVenue = home.mean('homeCornersFor', 20, leagueHome);
    final awayVenue = away.mean('awayCornersFor', 20, leagueAway);
    final baselineHome =
        0.35 * homeAttack +
        0.25 * awayDefence +
        0.20 * homeVenue +
        0.20 * leagueHome;
    final baselineAway =
        0.35 * awayAttack +
        0.25 * homeDefence +
        0.20 * awayVenue +
        0.20 * leagueAway;
    final market = _marketProbabilities(row);
    final date = DateTime.parse(row.date);
    final restDifference =
        (_restDays(home, date) - _restDays(away, date)).clamp(-14, 14) / 14;
    return _BuiltFootballFeatures(
      baselineHome: baselineHome,
      baselineAway: baselineAway,
      values: [
        baselineHome,
        baselineAway,
        leagueHome,
        leagueAway,
        home.mean('cornersFor', 5, defaultTeam),
        home.mean('cornersAgainst', 5, defaultTeam),
        away.mean('cornersFor', 5, defaultTeam),
        away.mean('cornersAgainst', 5, defaultTeam),
        home.mean('cornersFor', 10, defaultTeam),
        away.mean('cornersFor', 10, defaultTeam),
        home.mean('shotsFor', 5, 13),
        away.mean('shotsFor', 5, 12),
        home.mean('shotsOnTargetFor', 5, 4.5),
        away.mean('shotsOnTargetFor', 5, 4.2),
        home.mean('goalsFor', 5, 1.5),
        away.mean('goalsFor', 5, 1.2),
        log(home.weightedGames + 1),
        log(away.weightedGames + 1),
        market.$1,
        market.$3,
        market.$4,
        restDifference,
      ],
    );
  }

  void update(FootballMatchRecord row) {
    if (!row.isComplete) {
      return;
    }
    final home = teams.putIfAbsent(row.homeTeam, _TeamState.new);
    final away = teams.putIfAbsent(row.awayTeam, _TeamState.new);
    final weight = row.division == league.code ? 1.0 : 0.55;
    home.add('cornersFor', row.homeCorners!.toDouble(), weight);
    home.add('cornersAgainst', row.awayCorners!.toDouble(), weight);
    home.add('homeCornersFor', row.homeCorners!.toDouble(), weight);
    away.add('cornersFor', row.awayCorners!.toDouble(), weight);
    away.add('cornersAgainst', row.homeCorners!.toDouble(), weight);
    away.add('awayCornersFor', row.awayCorners!.toDouble(), weight);
    _addIfPresent(home, 'shotsFor', row.homeShots, weight);
    _addIfPresent(away, 'shotsFor', row.awayShots, weight);
    _addIfPresent(home, 'shotsOnTargetFor', row.homeShotsOnTarget, weight);
    _addIfPresent(away, 'shotsOnTargetFor', row.awayShotsOnTarget, weight);
    _addIfPresent(home, 'goalsFor', row.homeGoals, weight);
    _addIfPresent(away, 'goalsFor', row.awayGoals, weight);
    final date = DateTime.parse(row.date);
    home.lastPlayed = date;
    away.lastPlayed = date;
    home.weightedGames += weight;
    away.weightedGames += weight;
    if (row.division == league.code) {
      leagueHomeCorners.add(row.homeCorners!.toDouble());
      leagueAwayCorners.add(row.awayCorners!.toDouble());
    }
  }

  static void _addIfPresent(
    _TeamState state,
    String key,
    int? value,
    double weight,
  ) {
    if (value != null) {
      state.add(key, value.toDouble(), weight);
    }
  }

  static int _restDays(_TeamState state, DateTime date) {
    final last = state.lastPlayed;
    return last == null ? 7 : date.difference(last).inDays.clamp(2, 30);
  }

  static (double, double, double, double) _marketProbabilities(
    FootballMatchRecord row,
  ) {
    final home = row.homeOdds ?? 2.35;
    final draw = row.drawOdds ?? 3.35;
    final away = row.awayOdds ?? 3.15;
    final rawHome = 1 / max(home, 1.01);
    final rawDraw = 1 / max(draw, 1.01);
    final rawAway = 1 / max(away, 1.01);
    final total = rawHome + rawDraw + rawAway;
    final overRaw = 1 / max(row.over25Odds ?? 2, 1.01);
    final underRaw = 1 / max(row.under25Odds ?? 2, 1.01);
    return (
      rawHome / total,
      rawDraw / total,
      rawAway / total,
      overRaw / (overRaw + underRaw),
    );
  }

  static double _tailMean(List<double> values, int limit, double fallback) {
    if (values.isEmpty) {
      return fallback;
    }
    final start = max(values.length - limit, 0);
    final selected = values.sublist(start);
    return selected.fold(0.0, (sum, value) => sum + value) / selected.length;
  }
}

class _TeamState {
  final Map<String, List<_WeightedValue>> values = {};
  DateTime? lastPlayed;
  double weightedGames = 0;

  void add(String key, double value, double weight) {
    values.putIfAbsent(key, () => []).add(_WeightedValue(value, weight));
  }

  double mean(String key, int limit, double fallback) {
    final items = values[key];
    if (items == null || items.isEmpty) {
      return fallback;
    }
    final start = max(items.length - limit, 0);
    var weightedTotal = fallback * 3;
    var totalWeight = 3.0;
    var age = 0;
    for (var index = items.length - 1; index >= start; index--) {
      final item = items[index];
      final weight = item.weight * pow(0.88, age).toDouble();
      weightedTotal += item.value * weight;
      totalWeight += weight;
      age++;
    }
    return weightedTotal / totalWeight;
  }
}

class _WeightedValue {
  const _WeightedValue(this.value, this.weight);

  final double value;
  final double weight;
}

class _BuiltFootballFeatures {
  const _BuiltFootballFeatures({
    required this.baselineHome,
    required this.baselineAway,
    required this.values,
  });

  final double baselineHome;
  final double baselineAway;
  final List<double> values;
}
