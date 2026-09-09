import 'dart:math';

import '../models/racing_mobile.dart';
import 'race_probability.dart';

/// Result of scoring the racing model against the HKJC win pool on the same
/// settled races.
class RacingMarketVerdict {
  const RacingMarketVerdict({
    required this.status,
    required this.message,
    required this.races,
    required this.modelLogLoss,
    required this.marketLogLoss,
    required this.uniformLogLoss,
    required this.confidence,
  });

  static const empty = RacingMarketVerdict(
    status: 'insufficient',
    message: '未有已結算且存有派彩前賠率的賽事，暫不出推介。',
    races: 0,
    modelLogLoss: 0,
    marketLogLoss: 0,
    uniformLogLoss: 0,
    confidence: 0,
  );

  /// `insufficient`, `behind` or `ahead`.
  final String status;
  final String message;

  /// Settled races carrying both a model price and a full win pool.
  final int races;

  /// Mean `-ln p(winner)` of the model alone, with no pool blending.
  final double modelLogLoss;

  /// Mean `-ln p(winner)` of the takeout-free pool of the same races.
  final double marketLogLoss;

  /// Mean `-ln p(winner)` of quoting every runner at `1 / fieldSize`.
  final double uniformLogLoss;

  /// Weakest of the two paired t-statistics, pool and uniform.
  final double confidence;

  bool get beatsMarket => status == 'ahead';
}

/// Minimum settled races before the comparison is allowed to mean anything.
const racingMarketMinimumRaces = 40;

/// One-sided ~95% threshold on the paired t-statistic of the log loss gain.
const racingMarketMinimumT = 1.64;

/// Scores the racing model against the HKJC win pool on races it never saw.
///
/// Only meetings run after the model's `trainedThrough` are scored, so the
/// weights are held fixed and the comparison is out of sample. Both sides price
/// the same field: the model from the stored pre-race feature row, the market
/// from the published win odds of the same race with the takeout removed.
/// Nothing is refit here, and the model side is never blended with the pool —
/// blending it would be scoring the market against itself.
RacingMarketVerdict evaluateRacingMarketBaseline({
  required MobileRacingDataset dataset,
  required MobileRacingModel? model,
  int minimumRaces = racingMarketMinimumRaces,
}) {
  if (model == null || !model.useWinModel) {
    return const RacingMarketVerdict(
      status: 'insufficient',
      message: '手機賽馬模型尚未訓練，未能與馬會獨贏池比較，暫不出推介。',
      races: 0,
      modelLogLoss: 0,
      marketLogLoss: 0,
      uniformLogLoss: 0,
      confidence: 0,
    );
  }
  final oddsByRace = <String, List<double?>>{};
  final finishByRace = <String, List<int>>{};
  for (final record in dataset.results) {
    final raceId = record['raceId'] as String?;
    final finish = (record['finishPosition'] as num?)?.toInt();
    if (raceId == null || finish == null) {
      continue;
    }
    oddsByRace
        .putIfAbsent(raceId, () => <double?>[])
        .add((record['winOdds'] as num?)?.toDouble());
    finishByRace.putIfAbsent(raceId, () => <int>[]).add(finish);
  }
  final rowsByRace = <String, List<RacingTrainingRow>>{};
  for (final row in dataset.rows) {
    if (row.date.compareTo(model.trainedThrough) <= 0) {
      continue;
    }
    rowsByRace.putIfAbsent(row.raceId, () => <RacingTrainingRow>[]).add(row);
  }
  final versusMarket = <double>[];
  final versusUniform = <double>[];
  var modelTotal = 0.0;
  var marketTotal = 0.0;
  var uniformTotal = 0.0;
  var scored = 0;
  final raceIds = rowsByRace.keys.toList()..sort();
  for (final raceId in raceIds) {
    final rows = rowsByRace[raceId]!;
    final odds = oddsByRace[raceId];
    final finishes = finishByRace[raceId];
    // The result records are written runner by runner alongside the training
    // rows, so a length mismatch means the two lists no longer describe the
    // same field and the race is dropped rather than paired by guesswork.
    if (odds == null ||
        finishes == null ||
        odds.length != rows.length ||
        rows.length < 3) {
      continue;
    }
    final winner = finishes.indexOf(1);
    if (winner < 0) {
      continue;
    }
    final market = poolProbabilities(odds);
    if (market.length != rows.length) {
      continue;
    }
    final modelProbabilities = conditionalLogit([
      for (final row in rows) _dot(model.winWeights, row.features),
    ]);
    final own = -log(max(modelProbabilities[winner], 1e-9));
    final pool = -log(max(market[winner], 1e-9));
    final uniform = -log(1 / rows.length);
    versusMarket.add(pool - own);
    versusUniform.add(uniform - own);
    modelTotal += own;
    marketTotal += pool;
    uniformTotal += uniform;
    scored++;
  }
  if (scored < minimumRaces) {
    return RacingMarketVerdict(
      status: 'insufficient',
      message: '模型訓練後已結算並存有賠率的賽事 $scored／$minimumRaces 場，未夠比較，暫不出推介。',
      races: scored,
      modelLogLoss: 0,
      marketLogLoss: 0,
      uniformLogLoss: 0,
      confidence: 0,
    );
  }
  final modelLogLoss = modelTotal / scored;
  final marketLogLoss = marketTotal / scored;
  final uniformLogLoss = uniformTotal / scored;
  final confidence = min(_pairedT(versusMarket), _pairedT(versusUniform));
  final ahead = confidence > racingMarketMinimumT;
  return RacingMarketVerdict(
    status: ahead ? 'ahead' : 'behind',
    message: ahead
        ? '$scored 場模型訓練後賽事中，模型 Log Loss ${modelLogLoss.toStringAsFixed(4)} '
              '在統計上勝過馬會獨贏池 ${marketLogLoss.toStringAsFixed(4)}，推介開放。'
        : '$scored 場模型訓練後賽事中，模型 Log Loss ${modelLogLoss.toStringAsFixed(4)} '
              '未在統計上勝過馬會獨贏池 ${marketLogLoss.toStringAsFixed(4)}，暫不出推介。',
    races: scored,
    modelLogLoss: modelLogLoss,
    marketLogLoss: marketLogLoss,
    uniformLogLoss: uniformLogLoss,
    confidence: confidence,
  );
}

double _dot(List<double> weights, List<double> features) {
  var value = 0.0;
  final length = min(weights.length, features.length);
  for (var index = 0; index < length; index++) {
    value += weights[index] * features[index];
  }
  return value;
}

/// Mean of [differences] divided by its own standard error.
///
/// A handful of races moves a log loss on its own, so a smaller number is not
/// yet an edge; zero is returned when the spread cannot be estimated, which
/// reads as no evidence.
double _pairedT(List<double> differences) {
  if (differences.length < 20) {
    return 0;
  }
  final mean =
      differences.reduce((sum, value) => sum + value) / differences.length;
  var variance = 0.0;
  for (final value in differences) {
    variance += pow(value - mean, 2);
  }
  variance /= differences.length - 1;
  final standardError = sqrt(variance / differences.length);
  return standardError <= 0 ? 0 : mean / standardError;
}
