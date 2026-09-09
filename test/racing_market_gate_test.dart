import 'dart:math';

import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/racing_market_gate.dart';
import 'package:flutter_test/flutter_test.dart';

MobileRacingModel _model({
  String trainedThrough = '2026-01-31',
  bool useWinModel = true,
  List<double> winWeights = const [1.0],
}) {
  return MobileRacingModel(
    version: 'v1',
    datasetVersion: 'd1',
    trainedThrough: trainedThrough,
    winWeights: winWeights,
    winIntercept: 0,
    placeWeights: const [1.0],
    placeIntercept: 0,
    useWinModel: useWinModel,
    usePlaceModel: true,
    trainingRaces: 100,
    holdoutRaces: 20,
    winLogLoss: 2.2,
    baselineWinLogLoss: 2.4,
    winBrier: 0.07,
    placeBrier: 0.16,
    baselinePlaceBrier: 0.18,
  );
}

/// Builds a dataset of settled races run after the model was trained.
///
/// [signal] scales the feature of the horse that actually wins, so a large
/// value makes the model sharper than the pool and zero makes it blind. The
/// quoted odds always price the field evenly apart from a mild edge on the
/// winner, which stands in for a pool that is right more often than chance.
MobileRacingDataset _settled({
  required int races,
  required double signal,
  int fieldSize = 8,
  double marketSignal = 0.6,
  bool withOdds = true,
  String date = '2026-02-10',
}) {
  final random = Random(7);
  final rows = <RacingTrainingRow>[];
  final results = <Map<String, Object?>>[];
  for (var race = 0; race < races; race++) {
    final raceId = 'R$race';
    final winner = random.nextInt(fieldSize);
    for (var runner = 0; runner < fieldSize; runner++) {
      final won = runner == winner;
      rows.add(
        RacingTrainingRow(
          raceId: raceId,
          date: date,
          fieldSize: fieldSize,
          won: won ? 1 : 0,
          placed: won ? 1 : 0,
          features: [won ? signal : random.nextDouble() * 0.05],
        ),
      );
      final probability = won
          ? (1 + marketSignal) / fieldSize
          : (1 - marketSignal / (fieldSize - 1)) / fieldSize;
      results.add({
        'raceId': raceId,
        'horseId': '$raceId-$runner',
        'finishPosition': won ? 1 : runner + 2,
        if (withOdds) 'winOdds': 1 / probability,
      });
    }
  }
  return MobileRacingDataset(
    schemaVersion: 1,
    datasetVersion: 'd1',
    trainedThrough: date,
    featureNames: const ['f0'],
    rows: rows,
    horses: const {},
    jockeys: const {},
    trainers: const {},
    results: results,
  );
}

void main() {
  group('racing market baseline gate', () {
    test('an untrained model cannot be compared with the pool', () {
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 60, signal: 4),
        model: _model(useWinModel: false),
      );
      expect(verdict.status, 'insufficient');
      expect(verdict.beatsMarket, isFalse);
      expect(verdict.races, 0);
      expect(verdict.message, contains('尚未訓練'));
    });

    test('too few settled races leave the gate shut', () {
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 10, signal: 4),
        model: _model(),
      );
      expect(verdict.status, 'insufficient');
      expect(verdict.races, 10);
      expect(verdict.message, contains('10／40'));
    });

    test('races without stored win odds are not scored', () {
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 60, signal: 4, withOdds: false),
        model: _model(),
      );
      expect(verdict.status, 'insufficient');
      expect(verdict.races, 0);
    });

    test('races the model was trained on are not scored', () {
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 60, signal: 4, date: '2025-12-01'),
        model: _model(),
      );
      expect(verdict.races, 0);
      expect(verdict.status, 'insufficient');
    });

    test('a model no sharper than the pool keeps the gate shut', () {
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 60, signal: 0),
        model: _model(),
      );
      expect(verdict.status, 'behind');
      expect(verdict.beatsMarket, isFalse);
      expect(verdict.confidence, lessThan(racingMarketMinimumT));
      expect(verdict.modelLogLoss, greaterThan(verdict.marketLogLoss));
      expect(verdict.message, contains('未在統計上勝過'));
    });

    test('a model that beats the pool out of sample opens the gate', () {
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 60, signal: 4),
        model: _model(),
      );
      expect(verdict.status, 'ahead');
      expect(verdict.beatsMarket, isTrue);
      expect(verdict.races, 60);
      expect(verdict.confidence, greaterThan(racingMarketMinimumT));
      expect(verdict.modelLogLoss, lessThan(verdict.marketLogLoss));
      expect(verdict.uniformLogLoss, closeTo(log(8), 1e-9));
    });

    test('beating the pool but not a uniform field keeps the gate shut', () {
      // Zero weights price every runner at 1 / fieldSize, so the model ties the
      // uniform baseline no matter how weak the pool is.
      final verdict = evaluateRacingMarketBaseline(
        dataset: _settled(races: 60, signal: 4, marketSignal: -0.6),
        model: _model(winWeights: const [0]),
      );
      expect(verdict.status, 'behind');
      expect(verdict.modelLogLoss, lessThan(verdict.marketLogLoss));
      expect(verdict.confidence, lessThanOrEqualTo(0));
    });
  });
}
