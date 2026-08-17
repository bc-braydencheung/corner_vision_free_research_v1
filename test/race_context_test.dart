import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/race_context.dart';
import 'package:edgewise/services/racing_mobile_engine.dart';
import 'package:edgewise/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';

MobileEntityState _horse({
  Map<int, int> distanceStarts = const {},
  int starts = 0,
}) => MobileEntityState(starts: starts, distanceStarts: {...distanceStarts});

RacingWeatherSnapshot _reading({
  double rainfallMm = 0,
  double humidity = 0.7,
  String raceId = 'HK:2026-08-16:ST:1',
}) => RacingWeatherSnapshot(
  raceId: raceId,
  capturedAt: DateTime.utc(2026, 8, 16, 5),
  source: 'hko-rhrread',
  district: 'Sha Tin',
  validAt: DateTime.utc(2026, 8, 16, 5),
  temperatureC: 31,
  humidity: humidity,
  rainfallMm: rainfallMm,
);

Map<String, Object?> _race({
  required int runners,
  String venueCode = 'ST',
  String going = 'GOOD',
  int distance = 1400,
  String raceId = 'HK:2026-08-16:ST:1',
}) => {
  'raceId': raceId,
  'date': '2026-08-16',
  'venueCode': venueCode,
  'surface': 'TURF',
  'raceClass': '3',
  'distanceMetres': distance,
  'going': going,
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

MobileRacingDataset _dataset({Map<String, MobileEntityState>? horses}) =>
    MobileRacingDataset(
      schemaVersion: 1,
      datasetVersion: 'test',
      trainedThrough: '2026-07-15',
      featureNames: const [],
      rows: [],
      horses: horses ?? {},
      jockeys: {},
      trainers: {},
    );

HkjcFootballFixture _fixture({List<HkjcMarketLine> lines = const []}) =>
    HkjcFootballFixture(
      matchId: 'm1',
      frontEndId: 'FB1',
      leagueCode: 'E0',
      tournamentCode: 'EPL',
      tournamentName: '英格蘭超級聯賽',
      kickOffTime: DateTime.utc(2026, 8, 22, 14),
      status: 'PREEVENT',
      homeTeam: '阿仙奴',
      awayTeam: '利物浦',
      homeTeamEnglish: 'Arsenal',
      awayTeamEnglish: 'Liverpool',
      cornerLines: lines,
    );

void main() {
  group('pace', () {
    test('short trip record reads as early speed, long trip as a closer', () {
      final sprinter = _horse(distanceStarts: {5: 4, 6: 3});
      final stayer = _horse(distanceStarts: {9: 4, 10: 3});
      expect(sprintBias(sprinter, 1400), greaterThan(0.9));
      expect(sprintBias(stayer, 1400), lessThan(-0.9));
    });

    test('thin distance record claims nothing', () {
      expect(sprintBias(_horse(distanceStarts: {5: 2}), 1400), 0);
      expect(sprintBias(_horse(), 1400), 0);
    });

    test('scenario follows the share of early speed', () {
      expect(
        classifyPace(const [0.9, 0.8, 0.7, 0.1, -0.2, -0.4]),
        PaceScenario.fast,
      );
      expect(
        classifyPace(const [-0.9, -0.8, -0.7, -0.5, -0.6, -0.4]),
        PaceScenario.slow,
      );
      expect(
        classifyPace(const [0.9, 0.1, -0.2, -0.4, -0.5, -0.6, 0.0, 0.2, -0.1]),
        PaceScenario.even,
      );
      expect(classifyPace(const [0.9, 0.9]), PaceScenario.even);
    });

    test('a fast pace penalises early speed and helps closers', () {
      expect(paceAdjustment(PaceScenario.fast, 1), lessThan(0));
      expect(paceAdjustment(PaceScenario.fast, -1), greaterThan(0));
      expect(paceAdjustment(PaceScenario.slow, 1), greaterThan(0));
      expect(paceAdjustment(PaceScenario.even, 1), 0);
      expect(paceAdjustment(PaceScenario.fast, 1).abs(), lessThan(0.1));
    });
  });

  group('draw', () {
    test('inside stalls are favoured and the effect is bounded', () {
      final inside = drawBias(
        venueCode: 'HV',
        distanceMetres: 1200,
        draw: 1,
        fieldSize: 12,
      );
      final outside = drawBias(
        venueCode: 'HV',
        distanceMetres: 1200,
        draw: 12,
        fieldSize: 12,
      );
      expect(inside, greaterThan(0));
      expect(outside, lessThan(0));
      expect(inside.abs(), lessThanOrEqualTo(0.12));
    });

    test('the tight circuit and short trips matter most', () {
      final valley = drawBias(
        venueCode: 'HV',
        distanceMetres: 1200,
        draw: 1,
        fieldSize: 12,
      );
      final route = drawBias(
        venueCode: 'ST',
        distanceMetres: 2000,
        draw: 1,
        fieldSize: 12,
      );
      expect(valley, greaterThan(route));
    });

    test('a missing draw is not invented', () {
      expect(
        drawBias(
          venueCode: 'ST',
          distanceMetres: 1200,
          draw: null,
          fieldSize: 12,
        ),
        0,
      );
    });
  });

  group('context uncertainty', () {
    test('rainfall makes the surface wet even without a going report', () {
      const dry = RaceContext(
        venueCode: 'ST',
        distanceMetres: 1400,
        fieldSize: 8,
        going: 'GOOD',
      );
      final wet = RaceContext(
        venueCode: 'ST',
        distanceMetres: 1400,
        fieldSize: 8,
        going: 'GOOD',
        weather: _reading(rainfallMm: 4),
      );
      expect(dry.wet, isFalse);
      expect(wet.wet, isTrue);
      expect(wet.uncertainty, greaterThan(dry.uncertainty));
      expect(wet.label, contains('濕地'));
    });

    test('a wet big field never exceeds one', () {
      final extreme = RaceContext(
        venueCode: 'HV',
        distanceMetres: 1200,
        fieldSize: 14,
        going: '',
        weather: _reading(rainfallMm: 20, humidity: 0.98),
      );
      expect(extreme.uncertainty, lessThanOrEqualTo(1.0));
      expect(extreme.uncertainty, greaterThan(0.7));
    });
  });

  group('engine context integration', () {
    test('a wet race leans harder on the pool and lowers confidence', () {
      const engine = RacingMobileEngine();
      final pool = {
        'HK:2026-08-16:ST:1': {
          for (var index = 1; index <= 8; index++) '$index': 3.0 + index,
        },
      };
      final dry = engine.predictRaces(
        races: [_race(runners: 8)],
        dataset: _dataset(),
        poolOdds: pool,
      );
      final wet = engine.predictRaces(
        races: [_race(runners: 8)],
        dataset: _dataset(),
        poolOdds: pool,
        weather: {'HK:2026-08-16:ST:1': _reading(rainfallMm: 6)},
      );
      final dryRunner =
          (dry.first['runners'] as List).first as Map<String, Object?>;
      final wetRunner =
          (wet.first['runners'] as List).first as Map<String, Object?>;
      expect(
        wetRunner['poolWeight'] as double,
        greaterThan(dryRunner['poolWeight'] as double),
      );
      expect(
        wetRunner['confidenceScore'] as double,
        lessThan(dryRunner['confidenceScore'] as double),
      );
      expect(wetRunner['contextLabel'] as String, contains('Sha Tin'));
      expect((wetRunner['factors'] as List<String>).join(), contains('濕地'));
    });

    test('probabilities still sum to one with the context applied', () {
      const engine = RacingMobileEngine();
      final predicted = engine.predictRaces(
        races: [_race(runners: 10, venueCode: 'HV', distance: 1200)],
        dataset: _dataset(
          horses: {
            'H1': _horse(distanceStarts: {5: 5}),
            'H2': _horse(distanceStarts: {5: 4}),
            'H3': _horse(distanceStarts: {5: 4}),
            'H4': _horse(distanceStarts: {10: 5}),
          },
        ),
      );
      final runners = (predicted.first['runners'] as List)
          .cast<Map<String, Object?>>();
      final total = runners.fold<double>(
        0,
        (sum, runner) => sum + (runner['winProbability'] as double),
      );
      expect(total, closeTo(1, 1e-9));
      expect(runners.first['paceScenario'], isA<String>());
    });
  });

  group('free weather feeds', () {
    test('the Open-Meteo hourly block is parsed and matched to kick-off', () {
      final hours = parseOpenMeteoHourly(const {
        'hourly': {
          'time': ['2026-08-22T13:00', '2026-08-22T14:00'],
          'temperature_2m': [19.5, 20.5],
          'precipitation_probability': [10, 80],
          'wind_speed_10m': [12.0, 30.0],
        },
      });
      expect(hours, hasLength(2));
      final match = nearestHour(hours, DateTime.utc(2026, 8, 22, 14, 10));
      expect(match!.temperatureC, 20.5);
      expect(match.precipitationProbability, closeTo(0.8, 1e-9));
      expect(nearestHour(hours, DateTime.utc(2026, 8, 25)), isNull);
    });

    test('a malformed payload yields no hours', () {
      expect(parseOpenMeteoHourly(const {'hourly': 'none'}), isEmpty);
      expect(
        parseOpenMeteoHourly(const {
          'hourly': {
            'time': ['bad'],
            'temperature_2m': [1.0],
          },
        }),
        isEmpty,
      );
    });

    test('an Observatory district reading becomes a snapshot', () {
      final snapshot = parseHkoReading(
        const {
          'updateTime': '2026-08-16T13:02:00+08:00',
          'temperature': {
            'data': [
              {'place': 'Sha Tin', 'value': 32, 'unit': 'C'},
            ],
          },
          'humidity': {
            'data': [
              {'place': 'Hong Kong Observatory', 'value': 85},
            ],
          },
          'rainfall': {
            'data': [
              {'place': 'Sha Tin', 'max': 3, 'min': 0},
            ],
          },
        },
        district: 'Sha Tin',
        raceId: 'HK:2026-08-16:ST:1',
        capturedAt: DateTime.utc(2026, 8, 16, 5, 10),
      );
      expect(snapshot!.temperatureC, 32);
      expect(snapshot.humidity, closeTo(0.85, 1e-9));
      expect(snapshot.rainfallMm, 3);
      expect(snapshot.validAt.isUtc, isTrue);
    });

    test('an unknown district is skipped rather than guessed', () {
      expect(
        parseHkoReading(
          const {
            'temperature': {
              'data': [
                {'place': 'Sha Tin', 'value': 32},
              ],
            },
          },
          district: 'Happy Valley',
          raceId: 'r',
          capturedAt: DateTime.utc(2026, 8, 16),
        ),
        isNull,
      );
    });

    test('every tracked HKJC venue maps to an Observatory district', () {
      expect(hkjcWeatherDistricts.keys, containsAll(<String>['ST', 'HV']));
    });

    test('a fixture without a known venue gets no forecast request', () async {
      var called = false;
      final service = WeatherService(
        fetch: (url) async {
          called = true;
          return '{}';
        },
      );
      final unknown = HkjcFootballFixture(
        matchId: 'm2',
        frontEndId: 'FB2',
        leagueCode: 'E0',
        tournamentCode: 'EPL',
        tournamentName: '英格蘭超級聯賽',
        kickOffTime: DateTime.utc(2026, 8, 22, 14),
        status: 'PREEVENT',
        homeTeam: '未知',
        awayTeam: '未知',
        homeTeamEnglish: 'Nowhere Town',
        awayTeamEnglish: 'Elsewhere',
        cornerLines: const [],
      );
      expect(await service.footballForecast(unknown), isNull);
      expect(called, isFalse);
    });

    test('a known venue is forecast for the kick-off hour', () async {
      final service = WeatherService(
        fetch: (url) async {
          expect(url, contains('latitude=51.555'));
          return '{"hourly":{"time":["2026-08-22T14:00"],'
              '"temperature_2m":[18.0],'
              '"precipitation_probability":[70],'
              '"wind_speed_10m":[24.0]}}';
        },
      );
      final forecast = await service.footballForecast(_fixture());
      expect(forecast!.matchId, 'm1');
      expect(forecast.source, 'open-meteo');
      expect(forecast.precipitationProbability, closeTo(0.7, 1e-9));
    });

    test('a failing feed leaves the model without weather', () async {
      final service = WeatherService(fetch: (url) async => 'not json');
      expect(await service.footballForecast(_fixture()), isNull);
      expect(await service.racingObservations(const {'r': 'ST'}), isEmpty);
    });
  });

  group('weather driven corner dispersion', () {
    HkjcCornerModel model({FootballWeatherSnapshot? weather}) =>
        HkjcCornerModel(weather: weather);

    FootballWeatherSnapshot forecast({double rain = 0, double wind = 0}) =>
        FootballWeatherSnapshot(
          matchId: 'm1',
          capturedAt: DateTime.utc(2026, 8, 21),
          validAt: DateTime.utc(2026, 8, 22, 14),
          source: 'open-meteo',
          latitude: 51.555,
          longitude: -0.108,
          temperatureC: 18,
          precipitationProbability: rain,
          windSpeedKmh: wind,
        );

    test('no forecast keeps the count model Poisson', () {
      expect(model().dispersion, 0);
      expect(model().weatherNote, isNull);
    });

    test('rain and wind only widen the distribution', () {
      final windy = model(weather: forecast(rain: 0.9, wind: 40));
      expect(windy.dispersion, greaterThan(0));
      expect(windy.dispersion, lessThan(0.04));
      expect(windy.weatherNote, contains('降雨 90%'));
      expect(
        model(weather: forecast(rain: 0.9, wind: 40)).dispersion,
        greaterThan(model(weather: forecast(rain: 0.1, wind: 5)).dispersion),
      );
    });

    test('an extreme wind reading is capped', () {
      expect(
        model(weather: forecast(rain: 1, wind: 400)).dispersion,
        model(weather: forecast(rain: 1, wind: 45)).dispersion,
      );
    });
  });
}
