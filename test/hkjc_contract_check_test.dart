import 'package:edgewise/services/hkjc_contract_check.dart';
import 'package:edgewise/services/hkjc_football_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tournament list', () {
    test('a payload without the list is an interface change', () {
      final report = checkTournamentList(
        const {'data': <String, Object?>{}},
        profiles: hkjcFootballProfiles,
        resolved: const {},
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('沒有 tournamentList'));
    });

    test('an empty list is the off-season, not a change', () {
      final report = checkTournamentList(
        const {
          'data': {'tournamentList': <Object?>[]},
        },
        profiles: hkjcFootballProfiles,
        resolved: const {},
      );

      expect(report.marketClosed, isTrue);
      expect(report.interfaceChanged, isFalse);
    });

    test('renamed fields are an interface change', () {
      final report = checkTournamentList(
        const {
          'data': {
            'tournamentList': [
              {'tournamentId': '1', 'profile': '50000051'},
            ],
          },
        },
        profiles: hkjcFootballProfiles,
        resolved: const {},
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('id'));
      expect(report.message, contains('nameProfileId'));
    });

    test('tracked ids matching nothing is an interface change', () {
      final report = checkTournamentList(
        const {
          'data': {
            'tournamentList': [
              {'id': '50072572', 'nameProfileId': '60000051'},
            ],
          },
        },
        profiles: hkjcFootballProfiles,
        resolved: const {},
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('可能已改編號'));
    });

    test('a resolved season passes', () {
      final report = checkTournamentList(
        const {
          'data': {
            'tournamentList': [
              {'id': '50072572', 'nameProfileId': '50000051'},
            ],
          },
        },
        profiles: hkjcFootballProfiles,
        resolved: const {'50072572': 'E0'},
      );

      expect(report.status, 'ok');
      expect(report.message, isEmpty);
    });
  });

  group('match list', () {
    Map<String, Object?> payload(List<Map<String, Object?>> matches) => {
      'data': {'matches': matches},
    };

    test('a payload without matches is an interface change', () {
      final report = checkMatchList(
        const {'data': <String, Object?>{}},
        fixtures: 0,
        cornerPools: 0,
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('沒有 matches'));
    });

    test('no fixtures on sale is not an interface change', () {
      final report = checkMatchList(
        payload(const []),
        fixtures: 0,
        cornerPools: 0,
      );

      expect(report.marketClosed, isTrue);
      expect(report.message, contains('未開放'));
    });

    test('matches the parser cannot read are an interface change', () {
      final report = checkMatchList(
        payload(const [
          {
            'id': '1',
            'kickOffTime': '2026-01-01T12:00:00Z',
            'homeTeam': {'name_ch': '阿仙奴'},
            'awayTeam': {'name_ch': '車路士'},
            'foPools': <Object?>[],
          },
        ]),
        fixtures: 0,
        cornerPools: 0,
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('一場都解不出來'));
    });

    test('renamed match fields are an interface change', () {
      final report = checkMatchList(
        payload(const [
          {'matchId': '1', 'kickOff': '2026-01-01T12:00:00Z'},
        ]),
        fixtures: 0,
        cornerPools: 0,
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('kickOffTime'));
    });

    test('a dropped odds field is an interface change', () {
      final report = checkMatchList(
        payload(const [
          {
            'id': '1',
            'kickOffTime': '2026-01-01T12:00:00Z',
            'homeTeam': {'name_ch': '阿仙奴'},
            'awayTeam': {'name_ch': '車路士'},
          },
        ]),
        fixtures: 1,
        cornerPools: 0,
      );

      expect(report.interfaceChanged, isTrue);
      expect(report.message, contains('foPools'));
    });

    test('fixtures without a corner pool are a closed market', () {
      final report = checkMatchList(
        payload(const [
          {
            'id': '1',
            'kickOffTime': '2026-01-01T12:00:00Z',
            'homeTeam': {'name_ch': '阿仙奴'},
            'awayTeam': {'name_ch': '車路士'},
            'foPools': [
              {'oddsType': 'HAD'},
            ],
          },
        ]),
        fixtures: 1,
        cornerPools: 0,
      );

      expect(report.marketClosed, isTrue);
      expect(report.interfaceChanged, isFalse);
      expect(report.message, contains('未開角球大細盤'));
    });

    test('a readable card with corner pools passes', () {
      final report = checkMatchList(
        payload(const [
          {
            'id': '1',
            'kickOffTime': '2026-01-01T12:00:00Z',
            'homeTeam': {'name_ch': '阿仙奴'},
            'awayTeam': {'name_ch': '車路士'},
            'foPools': [
              {'oddsType': 'CHL'},
            ],
          },
        ]),
        fixtures: 1,
        cornerPools: 1,
      );

      expect(report.status, 'ok');
    });
  });
}
