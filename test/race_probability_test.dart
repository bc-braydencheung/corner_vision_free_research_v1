import 'dart:math';

import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/race_probability.dart';
import 'package:edgewise/services/racing_mobile_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _race({
  required int runners,
  String raceId = 'HK:2026-08-16:ST:9',
}) => {
  'raceId': raceId,
  'date': '2026-08-16',
  'venueCode': 'ST',
  'surface': 'TURF',
  'raceClass': '3',
  'distanceMetres': 1400,
  'runners': [
    for (var index = 1; index <= runners; index++)
      {
        'horseId': 'H$index',
        'number': index,
        'lastSix': index <= 2 ? '1/2/1' : '9/8/10',
        'weight': 126,
        'draw': index,
        'jockey': 'J$index',
        'trainer': 'T$index',
      },
  ],
};

MobileRacingDataset _dataset() => MobileRacingDataset(
  schemaVersion: 1,
  datasetVersion: 'test',
  trainedThrough: '2026-07-15',
  featureNames: const [],
  rows: [],
  horses: {},
  jockeys: {},
  trainers: {},
);

void main() {
  group('conditional logit', () {
    test('utilities become one race level distribution', () {
      final probabilities = conditionalLogit([1.0, 0.0, -1.0]);

      expect(probabilities.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(probabilities.first, greaterThan(probabilities.last));
      // A shift of every utility is not an event, so it cannot move anything.
      final shifted = conditionalLogit([4.0, 3.0, 2.0]);
      for (var index = 0; index < 3; index++) {
        expect(shifted[index], closeTo(probabilities[index], 1e-12));
      }
    });

    test('survives extreme utilities without overflowing', () {
      final probabilities = conditionalLogit([900.0, 0.0]);

      expect(probabilities.first, closeTo(1, 1e-9));
      expect(probabilities.last, closeTo(0, 1e-9));
      expect(conditionalLogit(const []), isEmpty);
    });
  });

  group('Harville place probabilities', () {
    test('the place probabilities sum to the number of paid places', () {
      final win = conditionalLogit([2.0, 1.4, 0.9, 0.4, 0.0, -0.6, -1.2, -2.0]);
      final place = harvillePlaceProbabilities(win, 3);

      expect(place.reduce((a, b) => a + b), closeTo(3, 1e-9));
      for (var index = 0; index < win.length; index++) {
        expect(place[index], greaterThan(win[index]));
        expect(place[index], lessThanOrEqualTo(1));
      }
      // Monotone in the win probability.
      expect(place.first, greaterThan(place.last));
    });

    test('an even field splits the places evenly', () {
      final win = List<double>.filled(10, 0.1);
      final place = harvillePlaceProbabilities(win, 3);

      for (final probability in place) {
        expect(probability, closeTo(0.3, 1e-9));
      }
    });

    test('the Henery discount moves place mass off the favourite', () {
      final win = conditionalLogit([3.0, 0.5, 0.2, 0.0, -0.4, -0.9, -1.5]);
      final harville = harvillePlaceProbabilities(win, 3);
      final henery = harvillePlaceProbabilities(win, 3, henery: 0.86);

      expect(henery.first, lessThan(harville.first));
      expect(henery.last, greaterThan(harville.last));
      expect(henery.reduce((a, b) => a + b), closeTo(3, 1e-9));
    });

    test('a field too small for a place pool pays nothing', () {
      expect(placeSlotsForField(3), 0);
      expect(placeSlotsForField(4), 2);
      expect(placeSlotsForField(7), 3);
      expect(harvillePlaceProbabilities(const [0.5, 0.3, 0.2], 0), [0, 0, 0]);
    });
  });

  group('pool prior', () {
    test('removes the takeout from a complete pool', () {
      final probabilities = poolProbabilities(const [2.0, 4.0, 6.0, 12.0]);

      expect(probabilities.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(probabilities.first, greaterThan(0.5 / 1.1));
    });

    test('refuses to normalise a partial pool', () {
      expect(poolProbabilities(const [2.0, null, null, null]), isEmpty);
      expect(poolProbabilities(const [2.0, 3.0, null, null]), isEmpty);
      expect(poolProbabilities(const [2.0, 3.0, 8.0, null]), isNotEmpty);
    });

    test('the favourite-longshot correction shifts mass to the favourite', () {
      final pool = poolProbabilities(const [2.0, 4.0, 8.0, 40.0]);
      final corrected = correctFavouriteLongshot(pool);

      expect(corrected.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(corrected.first, greaterThan(pool.first));
      expect(corrected.last, lessThan(pool.last));
      expect(
        correctFavouriteLongshot(pool, exponent: 1).first,
        closeTo(pool.first, 1e-12),
      );
    });

    test('the blend sits between the model and the market', () {
      final model = conditionalLogit([1.0, 0.5, 0.0]);
      final market = poolProbabilities(const [8.0, 3.0, 2.0]);
      final blended = blendDistributions(model, market, 0.45);

      expect(blended.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(blended.first, lessThan(model.first));
      expect(blended.first, greaterThan(market.first));
      expect(blendDistributions(model, market, 0).first, model.first);
      expect(
        blendDistributions(model, const [], 0.5).first,
        model.first,
        reason: 'no market means no blend',
      );
    });
  });

  test('entropy measures how little a race is separated', () {
    expect(normalisedEntropy(List<double>.filled(8, 0.125)), closeTo(1, 1e-12));
    expect(normalisedEntropy(const [0.97, 0.01, 0.01, 0.01]), lessThan(0.15));
  });

  group('engine integration', () {
    test('win probabilities form a race distribution and places expand it', () {
      final dataset = _dataset();
      final predicted = RacingMobileEngine().predictRaces(
        races: [_race(runners: 9)],
        dataset: dataset,
      );
      final runners = predicted.single['runners'] as List<Map<String, Object?>>;

      final win = runners
          .map((runner) => runner['winProbability'] as double)
          .toList();
      final place = runners
          .map((runner) => runner['placeProbability'] as double)
          .toList();
      expect(win.reduce((a, b) => a + b), closeTo(1, 1e-9));
      expect(place.reduce((a, b) => a + b), closeTo(3, 1e-9));
      expect(runners.first['poolWeight'], 0.0);
      expect(runners.first.containsKey('marketWinProbability'), isFalse);
      // Without a fitted ranking model the confidence stays capped.
      for (final runner in runners) {
        expect(runner['confidenceScore'] as double, lessThanOrEqualTo(0.54));
      }
    });

    test('the stored win pool pulls the probabilities towards the market', () {
      final dataset = _dataset();
      const engine = RacingMobileEngine();
      final race = _race(runners: 6);
      final baseline = engine.predictRaces(races: [race], dataset: dataset);
      final withPool = engine.predictRaces(
        races: [race],
        dataset: dataset,
        poolOdds: const {
          'HK:2026-08-16:ST:9': {
            'H1': 20.0,
            'H2': 15.0,
            'H3': 2.1,
            'H4': 6.0,
            'H5': 9.0,
            'H6': 12.0,
          },
        },
      );

      double win(List<Map<String, Object?>> runners, int index) =>
          runners[index]['winProbability'] as double;
      final before = baseline.single['runners'] as List<Map<String, Object?>>;
      final after = withPool.single['runners'] as List<Map<String, Object?>>;

      expect(win(after, 2), greaterThan(win(before, 2)));
      expect(win(after, 0), lessThan(win(before, 0)));
      expect(
        after.first['poolWeight'] as double,
        greaterThanOrEqualTo(RacingMobileEngine.poolWeight),
      );
      expect(after[2]['marketWinProbability'] as double, greaterThan(0.4));
      expect(
        (after.map(
          (runner) => runner['winProbability'] as double,
        )).reduce((a, b) => a + b),
        closeTo(1, 1e-9),
      );
      expect(
        after[2]['factors'] as List<String>,
        contains('馬會獨贏池先驗（已修正熱門–冷門偵斜）'),
      );
    });

    test('a partial pool is ignored rather than half applied', () {
      final dataset = _dataset();
      const engine = RacingMobileEngine();
      final race = _race(runners: 6);
      final baseline = engine.predictRaces(races: [race], dataset: dataset);
      final withPartial = engine.predictRaces(
        races: [race],
        dataset: dataset,
        poolOdds: const {
          'HK:2026-08-16:ST:9': {'H3': 2.1, 'H4': 6.0},
        },
      );

      final before = baseline.single['runners'] as List<Map<String, Object?>>;
      final after = withPartial.single['runners'] as List<Map<String, Object?>>;
      for (var index = 0; index < before.length; index++) {
        expect(
          after[index]['winProbability'] as double,
          closeTo(before[index]['winProbability'] as double, 1e-12),
        );
      }
    });

    test('fair odds are the reciprocal of the published probability', () {
      final dataset = _dataset();
      final runners =
          RacingMobileEngine()
                  .predictRaces(races: [_race(runners: 8)], dataset: dataset)
                  .single['runners']
              as List<Map<String, Object?>>;

      for (final runner in runners) {
        final win = runner['winProbability'] as double;
        expect(runner['fairWinOdds'] as double, closeTo(1 / win, 1e-9));
        expect(
          runner['fairPlaceOdds'] as double,
          closeTo(1 / max(runner['placeProbability'] as double, 0.001), 1e-9),
        );
      }
    });
  });
}
