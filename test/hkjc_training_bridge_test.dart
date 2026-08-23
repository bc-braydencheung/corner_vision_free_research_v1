import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/hkjc_training_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final kickOff = DateTime.utc(2026, 8, 22, 15);
  final asOf = kickOff.add(const Duration(hours: 6));

  FootballMatchRecord published({
    String division = 'SP1',
    String date = '2026-08-15',
    String homeTeam = 'Ath Bilbao',
    String awayTeam = 'Sevilla',
  }) => FootballMatchRecord(
    division: division,
    date: date,
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    homeCorners: 5,
    awayCorners: 4,
    homeShots: 12,
    awayShots: 9,
  );

  MobileFootballDataset datasetOf(List<FootballMatchRecord> rows) =>
      MobileFootballDataset(
        schemaVersion: 1,
        datasetVersion: 'v9',
        generatedAt: '2026-08-20T00:00:00Z',
        leagues: const [],
        rows: rows,
        fixtures: const [],
      );

  ShadowForecast forecast({
    String homeTeam = 'Ath Bilbao',
    String awayTeam = 'Sevilla',
    String leagueCode = 'SP1',
    String matchId = 'hkjc-1',
  }) => ShadowForecast(
    id: '$matchId:nb2',
    matchId: matchId,
    leagueCode: leagueCode,
    leagueName: '西甲',
    homeTeam: homeTeam,
    awayTeam: awayTeam,
    matchDate: kickOff,
    capturedAt: kickOff.subtract(const Duration(hours: 2)),
    modelVersion: 'nb2',
    expectedTotalCorners: 9.8,
    referenceMae: 2.6,
    referenceBrier: 0.24,
  );

  HkjcCornerResult result({
    String matchId = 'hkjc-1',
    int homeCorner = 10,
    int awayCorner = 3,
    DateTime? observedAt,
  }) => HkjcCornerResult(
    matchId: matchId,
    kickOffTime: kickOff,
    homeCorner: homeCorner,
    awayCorner: awayCorner,
    status: 'INPLAYMATCHENDED',
    observedAt: observedAt ?? asOf,
  );

  test('adds the finished HKJC match the free history has not published', () {
    final rows = hkjcTrainingRows(
      dataset: datasetOf([published()]),
      forecasts: [forecast()],
      results: [result()],
      asOf: asOf,
    );
    final row = rows.single;
    expect(row.division, 'SP1');
    expect(row.date, '2026-08-22');
    // Named as the free history names the club, not as HKJC names it.
    expect(row.homeTeam, 'Ath Bilbao');
    expect(row.awayTeam, 'Sevilla');
    expect(row.homeCorners, 10);
    expect(row.awayCorners, 3);
    // Nothing the reading does not carry is filled in.
    expect(row.homeShots, isNull);
    expect(row.homeGoals, isNull);
  });

  test('never adds a match the free history already carries', () {
    for (final date in const ['2026-08-21', '2026-08-22', '2026-08-23']) {
      final rows = hkjcTrainingRows(
        dataset: datasetOf([published(), published(date: date)]),
        forecasts: [forecast()],
        results: [result()],
        asOf: asOf,
      );
      expect(rows, isEmpty);
    }
  });

  test('resolves the club names the two feeds abbreviate differently', () {
    final rows = hkjcTrainingRows(
      dataset: datasetOf([
        published(division: 'E0', homeTeam: 'Man City', awayTeam: 'Man United'),
      ]),
      forecasts: [
        forecast(
          leagueCode: 'E0',
          homeTeam: 'Manchester City',
          awayTeam: 'Manchester Utd',
        ),
      ],
      results: [result()],
      asOf: asOf,
    );
    expect(rows.single.homeTeam, 'Man City');
    expect(rows.single.awayTeam, 'Man United');
  });

  test('never adds a club the free history does not carry', () {
    for (final unresolved in [
      forecast(homeTeam: '畢爾包', awayTeam: '西維爾'),
      forecast(homeTeam: 'Atl Bilbao'),
      forecast(leagueCode: 'E0'),
    ]) {
      expect(
        hkjcTrainingRows(
          dataset: datasetOf([published()]),
          forecasts: [unresolved],
          results: [result()],
          asOf: asOf,
        ),
        isEmpty,
      );
    }
  });

  test('never adds a reading that is not final or not possible', () {
    for (final reading in [
      // Taken while the match could still be running.
      result(observedAt: kickOff.add(const Duration(minutes: 30))),
      result(homeCorner: 30, awayCorner: 30),
      result(matchId: 'hkjc-2'),
    ]) {
      expect(
        hkjcTrainingRows(
          dataset: datasetOf([published()]),
          forecasts: [forecast()],
          results: [reading],
          asOf: asOf,
        ),
        isEmpty,
      );
    }
  });

  test('moves the dataset version with the rows it appended', () {
    final base = datasetOf([published()]);
    final augmented = withHkjcTrainingRows(
      dataset: base,
      forecasts: [forecast()],
      results: [result()],
      asOf: asOf,
    );
    expect(augmented.rows, hasLength(2));
    expect(augmented.rows.last.date, '2026-08-22');
    expect(augmented.datasetVersion, 'v9+hkjc1');

    final untouched = withHkjcTrainingRows(
      dataset: base,
      forecasts: const [],
      results: const [],
      asOf: asOf,
    );
    expect(untouched.datasetVersion, 'v9');
    expect(untouched.rows, hasLength(1));
  });
}
