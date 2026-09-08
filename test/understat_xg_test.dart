import 'dart:convert';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:edgewise/services/understat_xg_service.dart';
import 'package:flutter_test/flutter_test.dart';

String _payload(List<Map<String, Object?>> matches) => jsonEncode({
  'teams': <String, Object?>{},
  'players': <Object?>[],
  'dates': matches,
});

Map<String, Object?> _match({
  required String home,
  required String away,
  required String datetime,
  String homeXg = '1.5',
  String awayXg = '0.8',
  bool isResult = true,
}) => {
  'id': '1',
  'isResult': isResult,
  'h': {'id': '1', 'title': home, 'short_title': home},
  'a': {'id': '2', 'title': away, 'short_title': away},
  'goals': {'h': '1', 'a': '0'},
  'xG': {'h': homeXg, 'a': awayXg},
  'datetime': datetime,
};

FootballMatchRecord _row({
  required String date,
  required String home,
  required String away,
  String division = 'E0',
  int? homeCorners = 6,
  int? awayCorners = 4,
}) => FootballMatchRecord(
  division: division,
  date: date,
  homeTeam: home,
  awayTeam: away,
  homeCorners: homeCorners,
  awayCorners: awayCorners,
);

MobileFootballDataset _dataset(List<FootballMatchRecord> rows) =>
    MobileFootballDataset(
      schemaVersion: 2,
      datasetVersion: 'v1',
      generatedAt: '2026-01-01T00:00:00Z',
      leagues: const [
        FootballLeagueConfig(
          code: 'E0',
          name: '英超',
          supportCode: 'E1',
          supportName: '英冠',
        ),
      ],
      rows: rows,
      fixtures: const [],
    );

void main() {
  group('understat payload', () {
    test('reads settled matches only', () {
      final records = parseUnderstatLeagueData(
        _payload([
          _match(
            home: 'Liverpool',
            away: 'Bournemouth',
            datetime: '2025-08-15 19:00:00',
          ),
          _match(
            home: 'Arsenal',
            away: 'Chelsea',
            datetime: '2025-08-16 14:00:00',
            isResult: false,
          ),
        ]),
        division: 'E0',
      );
      expect(records, hasLength(1));
      expect(records.single.homeTeam, 'Liverpool');
      expect(records.single.date, '2025-08-15');
      expect(records.single.homeXg, closeTo(1.5, 1e-9));
      expect(records.single.awayXg, closeTo(0.8, 1e-9));
    });

    test('drops a match without a readable reading', () {
      final records = parseUnderstatLeagueData(
        _payload([
          {
            'isResult': true,
            'h': {'title': 'Liverpool'},
            'a': {'title': 'Everton'},
            'xG': {'h': null, 'a': '1.0'},
            'datetime': '2025-08-15 19:00:00',
          },
        ]),
        division: 'E0',
      );
      expect(records, isEmpty);
    });

    test('rejects a payload that no longer carries matches', () {
      expect(
        () => parseUnderstatLeagueData(
          jsonEncode({'teams': <String, Object?>{}}),
          division: 'E0',
        ),
        throwsFormatException,
      );
    });
  });

  group('merge', () {
    test('attaches a reading to the stored match', () {
      final merged = mergeUnderstatXg(
        dataset: _dataset([
          _row(date: '2025-08-15', home: 'Liverpool', away: 'Bournemouth'),
        ]),
        readings: const [
          UnderstatXgRecord(
            division: 'E0',
            date: '2025-08-15',
            homeTeam: 'Liverpool',
            awayTeam: 'Bournemouth',
            homeXg: 2.33,
            awayXg: 1.57,
          ),
        ],
      );
      expect(merged.dataset.rows.single.homeXg, closeTo(2.33, 1e-9));
      expect(merged.dataset.rows.single.awayXg, closeTo(1.57, 1e-9));
      expect(merged.coverage.matched, 1);
      expect(merged.coverage.rowsWithXg, 1);
      expect(merged.dataset.datasetVersion, 'v1+xg1');
    });

    test('matches a kick-off filed on the neighbouring day', () {
      final merged = mergeUnderstatXg(
        dataset: _dataset([
          _row(date: '2025-08-16', home: 'Liverpool', away: 'Bournemouth'),
        ]),
        readings: const [
          UnderstatXgRecord(
            division: 'E0',
            date: '2025-08-15',
            homeTeam: 'Liverpool',
            awayTeam: 'Bournemouth',
            homeXg: 2.0,
            awayXg: 1.0,
          ),
        ],
      );
      expect(merged.dataset.rows.single.homeXg, closeTo(2.0, 1e-9));
    });

    test('resolves a club the two feeds spell differently', () {
      final merged = mergeUnderstatXg(
        dataset: _dataset([
          _row(date: '2025-08-15', home: 'Man City', away: "Nott'm Forest"),
        ]),
        readings: const [
          UnderstatXgRecord(
            division: 'E0',
            date: '2025-08-15',
            homeTeam: 'Manchester City',
            awayTeam: 'Nottingham Forest',
            homeXg: 2.4,
            awayXg: 0.6,
          ),
        ],
      );
      expect(merged.dataset.rows.single.homeXg, closeTo(2.4, 1e-9));
    });

    test('drops a reading whose clubs the history does not carry', () {
      final dataset = _dataset([
        _row(date: '2025-08-15', home: 'Liverpool', away: 'Bournemouth'),
      ]);
      final merged = mergeUnderstatXg(
        dataset: dataset,
        readings: const [
          UnderstatXgRecord(
            division: 'E0',
            date: '2025-08-15',
            homeTeam: 'Some Reserve XI',
            awayTeam: 'Another Reserve XI',
            homeXg: 2.0,
            awayXg: 1.0,
          ),
        ],
      );
      expect(merged.dataset.rows.single.homeXg, isNull);
      expect(merged.coverage.matched, 0);
      expect(merged.coverage.unmatched, 1);
      expect(merged.dataset.datasetVersion, 'v1');
    });

    test('never moves a reading across divisions', () {
      final merged = mergeUnderstatXg(
        dataset: _dataset([
          _row(
            date: '2025-08-15',
            home: 'Liverpool',
            away: 'Bournemouth',
            division: 'E1',
          ),
        ]),
        readings: const [
          UnderstatXgRecord(
            division: 'E0',
            date: '2025-08-15',
            homeTeam: 'Liverpool',
            awayTeam: 'Bournemouth',
            homeXg: 2.0,
            awayXg: 1.0,
          ),
        ],
      );
      expect(merged.dataset.rows.single.homeXg, isNull);
    });

    test('reports how much of the settled history is covered', () {
      final merged = mergeUnderstatXg(
        dataset: _dataset([
          _row(date: '2025-08-15', home: 'Liverpool', away: 'Bournemouth'),
          _row(date: '2025-08-16', home: 'Arsenal', away: 'Chelsea'),
        ]),
        readings: const [
          UnderstatXgRecord(
            division: 'E0',
            date: '2025-08-15',
            homeTeam: 'Liverpool',
            awayTeam: 'Bournemouth',
            homeXg: 2.0,
            awayXg: 1.0,
          ),
        ],
      );
      expect(merged.coverage.settledRows, 2);
      expect(merged.coverage.rowsWithXg, 1);
      expect(merged.coverage.summary, '1／2 場有 xG');
    });
  });

  group('feed', () {
    test('reads both seasons of every covered division', () async {
      final requested = <Uri>[];
      final service = UnderstatXgService(
        fetchOverride: (uri) async {
          requested.add(uri);
          return _payload([
            _match(
              home: 'Liverpool',
              away: 'Bournemouth',
              datetime: '2025-08-15 19:00:00',
            ),
          ]);
        },
      );
      final records = await service.fetchAll(
        divisions: const ['E0', 'E1'],
        asOf: DateTime.utc(2026, 3, 1),
      );
      expect(requested.map((uri) => uri.path).toList(), [
        '/main/getLeagueData/EPL/2025',
        '/main/getLeagueData/EPL/2024',
      ]);
      expect(records, hasLength(2));
    });

    test('a refused season leaves the other readings usable', () async {
      final service = UnderstatXgService(
        fetchOverride: (uri) async {
          if (uri.path.endsWith('2024')) {
            throw const FormatException('gone');
          }
          return _payload([
            _match(
              home: 'Liverpool',
              away: 'Bournemouth',
              datetime: '2025-08-15 19:00:00',
            ),
          ]);
        },
      );
      final records = await service.fetchAll(
        divisions: const ['E0'],
        asOf: DateTime.utc(2026, 3, 1),
      );
      expect(records, hasLength(1));
    });
  });

  test('an empty reading set leaves the history unchanged', () async {
    final dataset = _dataset([
      _row(date: '2025-08-15', home: 'Liverpool', away: 'Bournemouth'),
    ]);
    final merged = mergeUnderstatXg(dataset: dataset, readings: const []);
    expect(merged.dataset.rows.single.homeXg, isNull);
    expect(merged.coverage.rowsWithXg, 0);
    expect(merged.coverage.summary, '尚未有已結算賽果，未能對應 xG');
  });

  group('features', () {
    test('xG columns follow the readings and stay absent without them', () {
      const names = footballFeatureNames;
      final homeIndex = names.indexOf('主隊近5場xG');
      final awayConcededIndex = names.indexOf('客隊近5場被xG');
      expect(homeIndex, isNonNegative);
      expect(FootballMobileEngine.featureCount, names.length);

      List<double> lastFeatures(List<FootballMatchRecord> rows) {
        final built = FootballMobileEngine().buildTrainingRows(
          _dataset(rows),
          _dataset(rows).leagues.first,
        );
        return built.last.features;
      }

      final withoutXg = lastFeatures([
        _row(date: '2025-08-15', home: 'Liverpool', away: 'Bournemouth'),
        _row(date: '2025-08-22', home: 'Liverpool', away: 'Chelsea'),
      ]);
      final withXg = lastFeatures([
        _row(
          date: '2025-08-15',
          home: 'Liverpool',
          away: 'Bournemouth',
        ).withXg(home: 3.4, away: 0.4),
        _row(date: '2025-08-22', home: 'Liverpool', away: 'Chelsea'),
      ]);
      expect(withXg[homeIndex], greaterThan(withoutXg[homeIndex]));
      expect(withXg[homeIndex], lessThanOrEqualTo(3.4));
      expect(
        withXg[awayConcededIndex],
        closeTo(withoutXg[awayConcededIndex], 1e-9),
      );

      final ownReading = lastFeatures([
        _row(date: '2025-08-15', home: 'Liverpool', away: 'Bournemouth'),
        _row(
          date: '2025-08-22',
          home: 'Liverpool',
          away: 'Chelsea',
        ).withXg(home: 3.4, away: 0.4),
      ]);
      expect(ownReading[homeIndex], closeTo(withoutXg[homeIndex], 1e-9));
    });
  });

  test('a stored dataset keeps its readings through a round trip', () {
    final row = _row(
      date: '2025-08-15',
      home: 'Liverpool',
      away: 'Bournemouth',
    ).withXg(home: 2.1, away: 0.9);
    final restored = FootballMatchRecord.fromCompact(row.toCompact());
    expect(restored.homeXg, closeTo(2.1, 1e-9));
    expect(restored.awayXg, closeTo(0.9, 1e-9));
    expect(
      FootballMatchRecord.fromCompact(row.toCompact().sublist(0, 18)).homeXg,
      isNull,
    );
  });
}
