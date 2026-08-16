import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:edgewise/services/hkjc_football_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _hiLoLine({
  required String lineId,
  required String condition,
  required bool main,
  required String high,
  required String low,
  String status = 'AVAILABLE',
}) => {
  'lineId': lineId,
  'status': status,
  'condition': condition,
  'main': main,
  'combinations': [
    {'combId': '1', 'str': 'H', 'status': status, 'currentOdds': high},
    {'combId': '2', 'str': 'L', 'status': status, 'currentOdds': low},
  ],
};

Map<String, Object?> _payload() => {
  'data': {
    'matches': [
      {
        'id': '50072566',
        'frontEndId': 'FB2773',
        'kickOffTime': '2026-08-16T23:00:00.000+08:00',
        'status': 'PREEVENT',
        'homeTeam': {'name_en': 'Santander', 'name_ch': '桑坦德'},
        'awayTeam': {'name_en': 'Villarreal', 'name_ch': '維拉利爾'},
        'tournament': {
          'id': '50072540',
          'nameProfileId': '50000100',
          'code': 'SFL',
          'name_ch': '西班牙甲組聯賽',
          'name_en': 'Spanish Division 1',
        },
        'runningResult': null,
        'foPools': [
          {
            'oddsType': 'HAD',
            'status': 'SELLINGSTARTED',
            'lines': [
              {
                'lineId': '0',
                'status': 'AVAILABLE',
                'condition': '0.0',
                'main': true,
                'combinations': [
                  {'combId': '1', 'str': 'H', 'currentOdds': '3.05'},
                  {'combId': '2', 'str': 'A', 'currentOdds': '1.94'},
                  {'combId': '3', 'str': 'D', 'currentOdds': '3.45'},
                ],
              },
            ],
          },
          {
            'oddsType': 'CHL',
            'status': 'SELLINGSTARTED',
            'lines': [
              _hiLoLine(
                lineId: '2',
                condition: '10.5',
                main: false,
                high: '2.19',
                low: '1.60',
              ),
              _hiLoLine(
                lineId: '1',
                condition: '9.5',
                main: true,
                high: '1.78',
                low: '1.92',
              ),
            ],
          },
        ],
      },
      {
        'id': '50072999',
        'frontEndId': 'FB9999',
        'kickOffTime': '2026-08-22T03:00:00.000+08:00',
        'status': 'PREEVENT',
        'homeTeam': {'name_en': 'Arsenal', 'name_ch': '阿仙奴'},
        'awayTeam': {'name_en': 'Coventry', 'name_ch': '高雲地利'},
        'tournament': {
          'id': '50071337',
          'nameProfileId': '50000051',
          'code': 'EPL',
          'name_ch': '英格蘭超級聯賽',
          'name_en': 'English Premier League',
        },
        'runningResult': null,
        'foPools': [
          {
            'oddsType': 'HIL',
            'status': 'SELLINGSTARTED',
            'lines': [
              _hiLoLine(
                lineId: '1',
                condition: '2.5/3.0',
                main: true,
                high: '1.79',
                low: '1.91',
              ),
            ],
          },
        ],
      },
      {
        'id': '50060000',
        'frontEndId': 'FB0000',
        'kickOffTime': '2026-08-18T03:00:00.000+08:00',
        'status': 'PREEVENT',
        'homeTeam': {'name_en': 'Sweden A', 'name_ch': '甲'},
        'awayTeam': {'name_en': 'Sweden B', 'name_ch': '乙'},
        'tournament': {
          'id': '50066251',
          'nameProfileId': '50000104',
          'code': 'SAL',
          'name_ch': '瑞典超級聯賽',
          'name_en': 'Swedish Allsvenskan',
        },
        'runningResult': null,
        'foPools': const [],
      },
    ],
  },
};

void main() {
  final service = HkjcFootballService();
  const model = HkjcCornerModel();

  test('parses HKJC fixtures for the tracked tournaments only', () {
    final fixtures = service.parseMatches(_payload(), const {
      '50072540': 'SP1',
      '50071337': 'E0',
    });

    expect(fixtures.map((fixture) => fixture.leagueCode), ['SP1', 'E0']);
    final laLiga = fixtures.first;
    expect(laLiga.homeTeam, '桑坦德');
    expect(laLiga.matchOdds!.home, 3.05);
    expect(laLiga.matchOdds!.draw, 3.45);
    expect(laLiga.matchOdds!.away, 1.94);
    expect(laLiga.cornerLines.map((line) => line.condition), ['9.5', '10.5']);
    expect(laLiga.mainCornerLine!.condition, '9.5');
    expect(laLiga.mainCornerLine!.highOdds, 1.78);
  });

  test('falls back to the public tournid when the season id is unknown', () {
    final fixtures = service.parseMatches(_payload(), const {});

    expect(fixtures.map((fixture) => fixture.leagueCode), ['SP1', 'E0']);
  });

  test('reports a missing corner pool instead of a zero line', () {
    final fixtures = service.parseMatches(_payload(), const {'50071337': 'E0'});
    final epl = fixtures.firstWhere((fixture) => fixture.leagueCode == 'E0');

    expect(epl.hasCornerMarket, isFalse);
    expect(epl.mainCornerLine, isNull);
    expect(model.assess(epl), isNull);
    expect(epl.goalLines.single.line, closeTo(2.75, 1e-9));
    expect(epl.goalLines.single.components, [2.5, 3.0]);
  });

  test('removes the HKJC margin from a hi/lo pair', () {
    final fair = model.removeVig(1.78, 1.92)!;

    expect(fair.high + fair.low, closeTo(1, 1e-12));
    expect(fair.high, closeTo(0.5189, 0.0005));
    expect(fair.overround, closeTo(0.0827, 0.0005));
    expect(model.removeVig(1.78, null), isNull);
    expect(model.removeVig(0.9, 1.92), isNull);
  });

  test('fits one Poisson corner mean across every quoted line', () {
    final fixtures = service.parseMatches(_payload(), const {
      '50072540': 'SP1',
    });
    final assessment = model.assess(
      fixtures.firstWhere((fixture) => fixture.leagueCode == 'SP1'),
    )!;

    expect(assessment.expectedCorners, greaterThan(9));
    expect(assessment.expectedCorners, lessThan(11.5));
    expect(assessment.lines, hasLength(2));
    for (final line in assessment.lines) {
      expect(
        line.fairHighOdds,
        greaterThan(line.line.highOdds!),
        reason: 'vig-free odds must be longer than the quoted odds',
      );
      expect(line.fairLowOdds, greaterThan(line.line.lowOdds!));
      expect(
        line.modelHighProbability + line.modelLowProbability,
        closeTo(1, 1e-9),
      );
    }
  });

  test('suggests a direction only when the model disagrees with a line', () {
    final consistent = HkjcFootballFixture(
      matchId: 'm1',
      frontEndId: 'FB1',
      leagueCode: 'E0',
      tournamentCode: 'EPL',
      tournamentName: '英格蘭超級聯賽',
      kickOffTime: DateTime.utc(2026, 8, 22),
      status: 'PREEVENT',
      homeTeam: '主',
      awayTeam: '客',
      homeTeamEnglish: 'Home',
      awayTeamEnglish: 'Away',
      cornerLines: const [
        HkjcMarketLine(
          lineId: '1',
          condition: '9.5',
          line: 9.5,
          main: true,
          status: 'AVAILABLE',
          highOdds: 1.9,
          lowOdds: 1.9,
        ),
      ],
    );

    final single = model.assess(consistent)!;
    expect(single.hasEdge, isFalse);

    final mispriced = HkjcFootballFixture(
      matchId: 'm2',
      frontEndId: 'FB2',
      leagueCode: 'E0',
      tournamentCode: 'EPL',
      tournamentName: '英格蘭超級聯賽',
      kickOffTime: DateTime.utc(2026, 8, 22),
      status: 'PREEVENT',
      homeTeam: '主',
      awayTeam: '客',
      homeTeamEnglish: 'Home',
      awayTeamEnglish: 'Away',
      cornerLines: const [
        HkjcMarketLine(
          lineId: '1',
          condition: '8.5',
          line: 8.5,
          main: true,
          status: 'AVAILABLE',
          highOdds: 1.5,
          lowOdds: 2.5,
        ),
        HkjcMarketLine(
          lineId: '2',
          condition: '9.5',
          line: 9.5,
          main: false,
          status: 'AVAILABLE',
          highOdds: 3.2,
          lowOdds: 1.35,
        ),
      ],
    );

    final assessment = model.assess(mispriced)!;
    expect(assessment.hasEdge, isTrue);
    expect(assessment.bestDirection, anyOf('high', 'low'));
    expect(assessment.bestEdge, greaterThan(0.02));
  });

  test('serialises a snapshot through the cache format', () {
    final fixtures = service.parseMatches(_payload(), const {
      '50072540': 'SP1',
      '50071337': 'E0',
    });
    final snapshot = HkjcFootballSnapshot(
      capturedAt: DateTime.utc(2026, 8, 15, 12),
      fixtures: fixtures,
      note: '測試',
    );

    final restored = HkjcFootballSnapshot.fromJson(snapshot.toJson());

    expect(restored.capturedAt, snapshot.capturedAt);
    expect(restored.note, '測試');
    expect(restored.forLeague('SP1').single.mainCornerLine!.lowOdds, 1.92);
    expect(restored.forLeague('E0').single.cornerLines, isEmpty);
    expect(restored.forLeague('E1'), isEmpty);
  });

  test('tracks exactly the two requested public HKJC tournament profiles', () {
    expect(hkjcFootballProfiles, {'E0': '50000051', 'SP1': '50000100'});
    expect(HkjcFootballService.oddsTypes, contains('CHL'));
  });
}
