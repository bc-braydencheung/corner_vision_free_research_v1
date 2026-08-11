import 'dart:convert';
import 'dart:io';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/data_service.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:edgewise/services/racing_mobile_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled payload contains the five configured leagues', () async {
    final decoded =
        jsonDecode(await rootBundle.loadString('assets/data/latest.json'))
            as Map;
    final data = ForecastData.fromJson(decoded.cast<String, Object?>());

    expect(data.leagues.map((league) => league.code), [
      'E0',
      'SP1',
      'F1',
      'D1',
      'I1',
    ]);
    expect(
      data.leagues.every((league) => league.model.holdoutMatches > 0),
      isTrue,
    );
    expect(data.leagues.every((league) => !league.model.tradeEnabled), isTrue);
    expect(
      data.leagues.every((league) => league.model.tradePolicyReason.isNotEmpty),
      isTrue,
    );
    expect(data.racing.available, isTrue);
    expect(data.racing.model.holdoutRaces, greaterThan(0));
    expect(data.racing.model.tradePolicyStatus, 'challenger-only');
    expect(data.racing.model.tradeEnabled, isFalse);
    expect(data.racing.model.tradePolicyReason, isNotEmpty);
    for (final race in data.racing.races) {
      expect(
        race.runners.fold<double>(
          0,
          (total, runner) => total + runner.winProbability,
        ),
        closeTo(1, 0.02),
      );
    }
  });

  test('parses direct Football-Data result updates', () {
    final results = parseFootballDataResults(
      'E0',
      'Div,Date,HomeTeam,AwayTeam,HC,AC\n'
          'E0,13/07/26,Alpha,Beta,7,4\n',
    );

    expect(results.single.matchId, 'E0:2026-07-13:Alpha:Beta');
    expect(results.single.actualTotalCorners, 11);
  });

  test('bundles five-league mobile football history', () async {
    final bytes = await rootBundle.load(
      'assets/data/football_mobile_seed.json.gz',
    );
    final decoded = utf8.decode(gzip.decode(bytes.buffer.asUint8List()));
    final dataset = MobileFootballDataset.fromJson(
      (jsonDecode(decoded) as Map).cast<String, Object?>(),
    );

    expect(dataset.leagues.map((league) => league.code), [
      'E0',
      'SP1',
      'F1',
      'D1',
      'I1',
    ]);
    expect(dataset.rows.length, greaterThan(69000));
    expect(dataset.trainedThrough('E0'), '2026-05-24');
    final rows = FootballMobileEngine().buildTrainingRows(
      dataset,
      dataset.leagues.first,
    );
    expect(rows.length, greaterThan(9800));
    expect(rows.first.features, hasLength(FootballMobileEngine.featureCount));
    expect(
      FootballMobileEngine.poissonDistribution(
        10.2,
      ).fold<double>(0, (sum, value) => sum + value),
      closeTo(1, 0.000001),
    );
  });

  test('bundles a resumable mobile racing training seed', () async {
    final bytes = await rootBundle.load(
      'assets/data/racing_mobile_seed.json.gz',
    );
    final decoded = utf8.decode(gzip.decode(bytes.buffer.asUint8List()));
    final dataset = MobileRacingDataset.fromJson(
      (jsonDecode(decoded) as Map).cast<String, Object?>(),
    );

    expect(dataset.featureNames, hasLength(17));
    expect(dataset.rows.length, greaterThan(45000));
    expect(dataset.rows.first.date, startsWith('2021-'));
    expect(dataset.trainedThrough, '2026-07-15');
    expect(dataset.horses, isNotEmpty);

    final payload =
        jsonDecode(await rootBundle.loadString('assets/data/latest.json'))
            as Map;
    final races = (payload['racing'] as Map)['races'] as List;
    if (races.isNotEmpty) {
      final predictions = RacingMobileEngine().predictRaces(
        races: [(races.first as Map).cast<String, Object?>()],
        dataset: dataset,
      );
      final runners = predictions.single['runners'] as List<Object?>;
      expect(
        runners.fold<double>(
          0,
          (sum, value) =>
              sum +
              (((value as Map).cast<String, Object?>()['winProbability'] as num)
                  .toDouble()),
        ),
        closeTo(1, 0.001),
      );
      expect(
        ((runners.first as Map)['horseNameChinese'] as String),
        isNotEmpty,
      );
    }
  });
}
