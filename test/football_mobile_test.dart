import 'dart:io';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/services/football_mobile_service.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloads complete streamed results and upcoming fixtures', () async {
    final directory = await Directory.systemTemp.createTemp('football-sync-');
    final store = FootballStore(directory: directory);
    await store.saveDataset(_dataset());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var corrected = false;
    final listener = server.listen((request) async {
      final body = request.uri.path.endsWith('fixtures.csv')
          ? _fixturesCsv()
          : _resultCsv(
              request.uri.pathSegments.last.replaceAll('.csv', ''),
              homeCorners: corrected ? 7 : 6,
            );
      request.response.statusCode = HttpStatus.ok;
      final midpoint = body.length ~/ 2;
      request.response.write(body.substring(0, midpoint));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      request.response.write(body.substring(midpoint));
      await request.response.close();
    });
    try {
      final bundled = _bundledLeagues();
      final origin = 'http://${server.address.address}:${server.port}';
      final service = FootballMobileService(
        store: store,
        minimumInterval: Duration.zero,
        baseUrl: '$origin/mmz4281',
        fixturesUrl: '$origin/fixtures.csv',
      );
      final synced = await service.sync(bundled);

      expect(synced.status.newMatches, 10);
      expect(synced.status.hasNewResults, isTrue);
      expect(synced.status.fixturesChanged, isTrue);
      expect(
        synced.leagues.every((league) => league.forecasts.length == 1),
        isTrue,
      );
      expect((await store.loadDataset()).fixtures, hasLength(5));
      expect(await store.needsTraining(), isTrue);

      final duplicate = await service.sync(bundled);
      expect(duplicate.status.newMatches, 0);
      expect((await store.loadDataset()).rows, hasLength(15));

      corrected = true;
      final correction = await service.sync(bundled);
      expect(correction.status.newMatches, 0);
      expect(correction.status.message, contains('修正 10 場'));
      expect((await store.loadDataset()).rows.last.homeCorners, 7);
    } finally {
      await server.close(force: true);
      await listener.cancel();
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });
}

List<LeagueForecastData> _bundledLeagues() => [
  for (final league in _configs)
    LeagueForecastData(
      code: league.code,
      name: league.name,
      supportName: league.supportName,
      status: '測試',
      model: const ModelSummary(
        selectedCandidate: 'dynamic',
        selectedCandidateLabel: 'Dynamic',
        trainedThrough: '2026-07-01',
        firstSeason: '2024/25',
        lastSeason: '2025/26',
        trainingMatches: 100,
        supportMatches: 100,
        supportName: '次級聯賽',
        validationMatches: 10,
        holdoutMatches: 10,
        maeTotalCorners: 3,
        baselineMaeHoldout: 3,
        maeSkillVsDynamicPercent: 0,
        withinTwoHoldout: 0.5,
        brierOver9_5: 0.25,
        brierSkillOver9_5Percent: 0,
        calibrationErrorOver9_5: 0.05,
      ),
      forecasts: const [],
      recentBacktests: const [],
    ),
];

const _configs = [
  FootballLeagueConfig(
    code: 'E0',
    name: '英超',
    supportCode: 'E1',
    supportName: '英冠',
  ),
  FootballLeagueConfig(
    code: 'SP1',
    name: '西甲',
    supportCode: 'SP2',
    supportName: '西乙',
  ),
  FootballLeagueConfig(
    code: 'F1',
    name: '法甲',
    supportCode: 'F2',
    supportName: '法乙',
  ),
  FootballLeagueConfig(
    code: 'D1',
    name: '德甲',
    supportCode: 'D2',
    supportName: '德乙',
  ),
  FootballLeagueConfig(
    code: 'I1',
    name: '意甲',
    supportCode: 'I2',
    supportName: '意乙',
  ),
];

MobileFootballDataset _dataset() {
  return MobileFootballDataset(
    schemaVersion: 1,
    datasetVersion: 'initial',
    generatedAt: '2026-07-01T00:00:00Z',
    leagues: _configs,
    rows: [
      for (final league in _configs)
        FootballMatchRecord(
          division: league.code,
          date: '2026-07-01',
          homeTeam: '${league.code} Alpha',
          awayTeam: '${league.code} Beta',
          homeCorners: 5,
          awayCorners: 4,
          homeGoals: 2,
          awayGoals: 1,
          homeShots: 14,
          awayShots: 10,
          homeShotsOnTarget: 6,
          awayShotsOnTarget: 4,
        ),
    ],
    fixtures: const [],
  );
}

String _resultCsv(String division, {required int homeCorners}) {
  return 'Div,Date,HomeTeam,AwayTeam,FTHG,FTAG,HS,AS,HST,AST,HC,AC,AvgH,AvgD,AvgA,Avg>2.5,Avg<2.5\n'
      '$division,13/07/26,$division Alpha,$division Beta,1,1,12,11,4,4,$homeCorners,5,2.10,3.20,3.40,1.90,1.90\n';
}

String _fixturesCsv() {
  const divisions = ['E0', 'SP1', 'F1', 'D1', 'I1'];
  return 'Div,Date,HomeTeam,AwayTeam,AvgH,AvgD,AvgA,Avg>2.5,Avg<2.5\n'
      '${divisions.map((division) => '$division,20/07/26,$division Alpha,$division Gamma,1.90,3.30,3.80,1.85,1.95').join('\n')}\n';
}
