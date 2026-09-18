import 'dart:io';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/football_mobile_service.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'history download lands usable files, keeps failures and resumes',
    () async {
      final directory = await Directory.systemTemp.createTemp('football-dl-');
      final store = FootballStore(directory: directory);
      await store.saveDataset(_seed());
      final requested = <String>[];
      var secondLegAvailable = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final listener = server.listen((request) async {
        final name = request.uri.pathSegments.last.replaceAll('.csv', '');
        requested.add(name);
        if (name == 'fixtures') {
          request.response.write(_resultCsv('E0', corners: false));
          await request.response.close();
          return;
        }
        if (name == 'I2' && !secondLegAvailable) {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
          return;
        }
        request.response.write(_resultCsv(name, corners: name != 'SP2'));
        await request.response.close();
      });
      try {
        final origin = 'http://${server.address.address}:${server.port}';
        final service = FootballMobileService(
          store: store,
          minimumInterval: Duration.zero,
          baseUrl: '$origin/mmz4281',
          fixturesUrl: '$origin/fixtures.csv',
          firstSeasonYear: _currentSeasonStart(),
        );

        expect(await service.historyDownloadPending(_configs), isFalse);

        final first = await service.downloadHistory(leagues: _configs);
        expect(first.imported, 8);
        expect(first.withoutCorners, 1);
        expect(first.failed, 1);
        expect(first.rowsAdded, 8);
        expect(first.complete, isFalse);
        expect(first.failures.single.division, 'I2');
        expect(first.summary, contains('下載失敗'));
        expect(await store.needsTraining(), isTrue);
        // Rows without corner counts never reach the dataset, so the trainer
        // is not handed a null.
        final rows = (await store.loadDataset()).rows;
        expect(rows, hasLength(13));
        expect(rows.every((row) => row.homeCorners != null), isTrue);
        expect(rows.any((row) => row.division == 'SP2'), isFalse);
        expect(await service.historyDownloadPending(_configs), isTrue);

        requested.clear();
        secondLegAvailable = true;
        final second = await service.downloadHistory(leagues: _configs);
        // Only the file that failed is fetched again.
        expect(requested.where((name) => name != 'fixtures'), ['I2']);
        expect(second.imported, 1);
        expect(
          second.tasks.where((task) => task.status == 'skipped'),
          hasLength(9),
        );
        expect(second.complete, isTrue);
        expect(second.summary, isNot(contains('下載失敗')));
        expect((await store.loadDataset()).rows, hasLength(14));
        expect(await service.historyDownloadPending(_configs), isFalse);

        final report = await store.loadSourceReport();
        expect(report?['pendingTasks'], 0);
      } finally {
        await server.close(force: true);
        await listener.cancel();
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test('a restart fetches every season file again', () async {
    final directory = await Directory.systemTemp.createTemp('football-dl2-');
    final store = FootballStore(directory: directory);
    await store.saveDataset(_seed());
    final requested = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final listener = server.listen((request) async {
      final name = request.uri.pathSegments.last.replaceAll('.csv', '');
      requested.add(name);
      request.response.write(_resultCsv(name, corners: true));
      await request.response.close();
    });
    try {
      final origin = 'http://${server.address.address}:${server.port}';
      final service = FootballMobileService(
        store: store,
        minimumInterval: Duration.zero,
        baseUrl: '$origin/mmz4281',
        fixturesUrl: '$origin/fixtures.csv',
        firstSeasonYear: _currentSeasonStart(),
      );
      await service.downloadHistory(leagues: _configs);
      requested.clear();

      final again = await service.downloadHistory(
        leagues: _configs,
        restart: true,
      );

      expect(requested.where((name) => name != 'fixtures'), hasLength(10));
      expect(again.imported, 10);
      // The files carry rows that already landed, so nothing is duplicated.
      expect(again.rowsAdded, 0);
      expect((await store.loadDataset()).rows, hasLength(15));
    } finally {
      await server.close(force: true);
      await listener.cancel();
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  });
}

int _currentSeasonStart() {
  final now = DateTime.now().toUtc();
  return now.month >= 7 ? now.year : now.year - 1;
}

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

MobileFootballDataset _seed() => MobileFootballDataset(
  schemaVersion: FootballStore.supportedSchemaVersion,
  datasetVersion: 'seed',
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
      ),
  ],
  fixtures: const [],
);

/// A one-row season file, optionally without the corner columns that early
/// free seasons of several divisions are missing.
String _resultCsv(String division, {required bool corners}) {
  final header = corners
      ? 'Div,Date,HomeTeam,AwayTeam,FTHG,FTAG,HC,AC'
      : 'Div,Date,HomeTeam,AwayTeam,FTHG,FTAG';
  final row = corners
      ? '$division,13/07/26,$division Home,$division Away,1,1,6,5'
      : '$division,13/07/26,$division Home,$division Away,1,1';
  return '$header\n$row\n';
}
