import 'dart:math';

import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/calibration.dart';
import 'package:edgewise/services/calibration_service.dart';
import 'package:edgewise/services/racing_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Racing store that serves an in-memory dataset and counts the reads.
class _FakeRacingStore extends RacingStore {
  _FakeRacingStore(this.dataset, this.model);

  MobileRacingDataset dataset;
  MobileRacingModel? model;
  int datasetLoads = 0;

  @override
  Future<MobileRacingDataset> loadDataset() async {
    datasetLoads++;
    return dataset;
  }

  @override
  Future<MobileRacingModel?> loadModel() async => model;
}

List<CalibrationSample> _samples({
  required int count,
  required double probability,
  required double trueRate,
  int seed = 7,
}) {
  final random = Random(seed);
  return [
    for (var index = 0; index < count; index++)
      CalibrationSample(
        probability: probability,
        outcome: random.nextDouble() < trueRate,
        observedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
      ),
  ];
}

void main() {
  group('scores', () {
    test('brier score of a perfect forecast is zero', () {
      final samples = [
        const CalibrationSample(probability: 1, outcome: true),
        const CalibrationSample(probability: 0, outcome: false),
      ];
      expect(brierScore(samples), closeTo(0, 1e-12));
    });

    test('brier score of a maximally wrong forecast is one', () {
      final samples = [
        const CalibrationSample(probability: 0, outcome: true),
        const CalibrationSample(probability: 1, outcome: false),
      ];
      expect(brierScore(samples), closeTo(1, 1e-12));
    });

    test('calibration error is zero when frequencies match', () {
      final samples = [
        for (var index = 0; index < 10; index++)
          CalibrationSample(probability: 0.5, outcome: index.isEven),
      ];
      final error = calibrationError(samples);
      expect(error.expected, closeTo(0, 1e-12));
      expect(error.maximum, closeTo(0, 1e-12));
    });

    test('calibration error reports the observed gap', () {
      final samples = [
        for (var index = 0; index < 10; index++)
          const CalibrationSample(probability: 0.9, outcome: false),
      ];
      expect(calibrationError(samples).expected, closeTo(0.9, 1e-12));
    });

    test('empty sample produces the empty report', () {
      final report = evaluateCalibration(const []);
      expect(report.samples, 0);
      expect(report.reliable, isFalse);
      expect(report.verdict, contains('樣本不足'));
    });
  });

  group('calibrators', () {
    test('small samples stay uncalibrated', () {
      final calibrator = fitCalibrator(
        _samples(count: 20, probability: 0.8, trueRate: 0.3),
      );
      expect(calibrator, isA<IdentityCalibrator>());
      expect(calibrator.reliable, isFalse);
      expect(calibrator.apply(0.8), closeTo(0.8, 1e-12));
    });

    test(
      'temperature scaling pulls an over-confident score to the base rate',
      () {
        final samples = _samples(count: 120, probability: 0.9, trueRate: 0.4);
        final calibrator = fitCalibrator(samples);
        expect(calibrator, isA<TemperatureCalibrator>());
        expect(calibrator.reliable, isTrue);
        expect(calibrator.apply(0.9), lessThan(0.9));
      },
    );

    test('isotonic regression is used once the sample is large', () {
      final random = Random(11);
      final samples = [
        for (var index = 0; index < 400; index++)
          () {
            final probability = random.nextDouble();
            return CalibrationSample(
              probability: probability,
              // Published score is twice as far from a half as the truth.
              outcome: random.nextDouble() < 0.5 + (probability - 0.5) / 2,
              observedAt: DateTime.utc(2026, 2, 1).add(Duration(hours: index)),
            );
          }(),
      ];
      final calibrator = fitCalibrator(samples);
      expect(calibrator, isA<IsotonicCalibrator>());
      expect(calibrator.reliable, isTrue);
      expect(calibrator.apply(0.95), lessThan(0.95));
      expect(calibrator.apply(0.05), greaterThan(0.05));
    });

    test('isotonic output never decreases', () {
      final random = Random(3);
      final samples = [
        for (var index = 0; index < 300; index++)
          CalibrationSample(
            probability: random.nextDouble(),
            outcome: random.nextBool(),
            observedAt: DateTime.utc(2026, 3, 1).add(Duration(hours: index)),
          ),
      ];
      final calibrator = fitCalibrator(samples) as IsotonicCalibrator;
      var previous = -1.0;
      for (var step = 0; step <= 20; step++) {
        final value = calibrator.apply(step / 20);
        expect(value, greaterThanOrEqualTo(previous - 1e-12));
        previous = value;
      }
    });

    test('calibration improves the reported brier score', () {
      final samples = _samples(count: 200, probability: 0.85, trueRate: 0.45);
      final raw = brierScore(samples);
      final calibrated = evaluateCalibration(samples);
      expect(calibrated.brier, lessThan(raw));
      expect(calibrated.expectedCalibrationError, lessThan(0.4));
    });

    test('a constant forecast cannot beat the base rate', () {
      final report = evaluateCalibration(
        _samples(count: 200, probability: 0.6, trueRate: 0.5),
      );
      expect(report.beatsBaseline, isFalse);
      expect(report.verdict, contains('未顯著勝過基準率'));
    });

    test('rolling window keeps only the most recent samples', () {
      final samples = _samples(count: 100, probability: 0.5, trueRate: 0.5);
      final window = rollingWindow(samples, size: 30);
      expect(window.length, 30);
      expect(window.last.observedAt, samples.last.observedAt);
      expect(window.first.observedAt, samples[70].observedAt);
    });
  });

  group('market calibration', () {
    test('football samples use settled corner counts only', () {
      final service = CalibrationService();
      final records = [
        ShadowForecast(
          id: 'a',
          matchId: 'm1',
          leagueCode: 'E0',
          leagueName: '英超',
          homeTeam: 'A',
          awayTeam: 'B',
          matchDate: DateTime.utc(2026, 1, 2),
          capturedAt: DateTime.utc(2026, 1, 1),
          modelVersion: 'v1',
          expectedTotalCorners: 10,
          over9_5Probability: 0.6,
          referenceMae: 3,
          referenceBrier: 0.25,
          actualTotalCorners: 12,
          settledAt: DateTime.utc(2026, 1, 3),
        ),
        ShadowForecast(
          id: 'b',
          matchId: 'm2',
          leagueCode: 'E0',
          leagueName: '英超',
          homeTeam: 'C',
          awayTeam: 'D',
          matchDate: DateTime.utc(2026, 1, 4),
          capturedAt: DateTime.utc(2026, 1, 3),
          modelVersion: 'v1',
          expectedTotalCorners: 9,
          over9_5Probability: 0.4,
          referenceMae: 3,
          referenceBrier: 0.25,
        ),
      ];
      final samples = service.footballSamples(records);
      expect(samples.length, 1);
      expect(samples.single.outcome, isTrue);
      expect(samples.single.probability, closeTo(0.6, 1e-12));
    });

    test('racing samples only cover races after the training cut-off', () {
      final service = CalibrationService();
      final dataset = MobileRacingDataset(
        schemaVersion: 1,
        datasetVersion: 'd1',
        trainedThrough: '2026-01-31',
        featureNames: const ['f0'],
        rows: [
          const RacingTrainingRow(
            raceId: 'old',
            date: '2026-01-10',
            fieldSize: 2,
            won: 1,
            placed: 1,
            features: [0.5],
          ),
          const RacingTrainingRow(
            raceId: 'old',
            date: '2026-01-10',
            fieldSize: 2,
            won: 0,
            placed: 0,
            features: [-0.5],
          ),
          const RacingTrainingRow(
            raceId: 'new',
            date: '2026-02-10',
            fieldSize: 2,
            won: 1,
            placed: 1,
            features: [0.8],
          ),
          const RacingTrainingRow(
            raceId: 'new',
            date: '2026-02-10',
            fieldSize: 2,
            won: 0,
            placed: 0,
            features: [-0.8],
          ),
        ],
        horses: const {},
        jockeys: const {},
        trainers: const {},
      );
      final model = MobileRacingModel(
        version: 'v1',
        datasetVersion: 'd1',
        trainedThrough: '2026-01-31',
        winWeights: const [1.5],
        winIntercept: 0,
        placeWeights: const [1.0],
        placeIntercept: 0,
        useWinModel: true,
        usePlaceModel: true,
        trainingRaces: 1,
        holdoutRaces: 1,
        winLogLoss: 0.6,
        baselineWinLogLoss: 0.7,
        winBrier: 0.2,
        placeBrier: 0.2,
        baselinePlaceBrier: 0.25,
      );
      final samples = service.racingSamples(dataset: dataset, model: model);
      expect(samples.win.length, 2);
      expect(
        samples.win
            .map((sample) => sample.probability)
            .reduce((left, right) => left + right),
        closeTo(1, 1e-9),
      );
      expect(samples.win.first.probability, greaterThan(0.5));
      // A two-horse field has no place pool, so nothing is graded there.
      expect(samples.place, isEmpty);
    });

    test('an unchanged racing dataset is not refitted', () async {
      final dataset = MobileRacingDataset(
        schemaVersion: 1,
        datasetVersion: 'd1',
        trainedThrough: '2026-01-31',
        featureNames: const ['f0'],
        rows: const [
          RacingTrainingRow(
            raceId: 'new',
            date: '2026-02-10',
            fieldSize: 2,
            won: 1,
            placed: 1,
            features: [0.8],
          ),
          RacingTrainingRow(
            raceId: 'new',
            date: '2026-02-10',
            fieldSize: 2,
            won: 0,
            placed: 0,
            features: [-0.8],
          ),
        ],
        horses: const {},
        jockeys: const {},
        trainers: const {},
      );
      final model = MobileRacingModel(
        version: 'v1',
        datasetVersion: 'd1',
        trainedThrough: '2026-01-31',
        winWeights: const [1.5],
        winIntercept: 0,
        placeWeights: const [1.0],
        placeIntercept: 0,
        useWinModel: true,
        usePlaceModel: true,
        trainingRaces: 1,
        holdoutRaces: 1,
        winLogLoss: 0.6,
        baselineWinLogLoss: 0.7,
        winBrier: 0.2,
        placeBrier: 0.2,
        baselinePlaceBrier: 0.25,
      );
      final store = _FakeRacingStore(dataset, model);
      final service = CalibrationService(racingStore: store);
      final first = await service.evaluate(const []);
      final second = await service.evaluate(const []);
      expect(store.datasetLoads, 2);
      expect(
        identical(first.racingWin, second.racingWin),
        isTrue,
        reason: 'an unchanged fingerprint must reuse the previous fit',
      );

      store.dataset = MobileRacingDataset(
        schemaVersion: dataset.schemaVersion,
        datasetVersion: dataset.datasetVersion,
        trainedThrough: dataset.trainedThrough,
        featureNames: dataset.featureNames,
        rows: [
          ...dataset.rows,
          const RacingTrainingRow(
            raceId: 'newer',
            date: '2026-03-10',
            fieldSize: 2,
            won: 1,
            placed: 1,
            features: [0.2],
          ),
        ],
        horses: const {},
        jockeys: const {},
        trainers: const {},
      );
      final third = await service.evaluate(const []);
      expect(identical(first.racingWin, third.racingWin), isFalse);
    });

    test('an unfitted market leaves the probability untouched', () {
      final calibration = MarketCalibration.none('角球大細 9.5');
      expect(calibration.apply(0.73), closeTo(0.73, 1e-12));
      expect(calibration.report.reliable, isFalse);
    });

    test('empty state exposes every market as insufficient sample', () {
      final state = CalibrationState.empty;
      expect(state.markets.length, 3);
      expect(state.anyReliable, isFalse);
      for (final market in state.markets) {
        expect(market.report.verdict, contains('樣本不足'));
      }
    });
  });
}
