import 'dart:convert';
import 'dart:io';

import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/services/calibration.dart';
import 'package:edgewise/services/calibration_service.dart';
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

    final pick = assessment.recommendation!;
    expect(pick.direction, assessment.bestDirection);
    expect(pick.edge, assessment.bestEdge);
    expect(
      pick.odds,
      pick.direction == 'high'
          ? pick.line.line.highOdds
          : pick.line.line.lowOdds,
    );
    expect(pick.directionLabel, pick.direction == 'high' ? '大' : '細');
    expect(pick.confidence, greaterThan(0));
    expect(pick.confidence, lessThanOrEqualTo(1));
    expect(pick.confidenceLabel, anyOf('高', '中', '低'));
    expect(pick.stakeFraction, greaterThan(0));
    expect(pick.stakeFraction, lessThanOrEqualTo(0.05));

    final declined = model.assess(consistent)!;
    expect(
      declined.recommendation,
      isNull,
      reason: 'a market that agrees with the model must not be recommended',
    );
    // A declined fixture still reports its least-bad side so the card can show
    // a probability and a confidence instead of nothing at all.
    final watched = declined.observation!;
    expect(watched.direction, anyOf('high', 'low'));
    expect(watched.edge, lessThan(0.02));
    expect(watched.winProbability, greaterThan(0));
    expect(watched.winProbability, lessThan(1));
    expect(watched.confidence, greaterThanOrEqualTo(0));
    expect(watched.confidence, lessThanOrEqualTo(1));
    expect(
      declined.lines.map((line) => line.line.lineId),
      contains(watched.line.line.lineId),
    );
  });

  test('confidence grows with the edge and with line agreement', () {
    HkjcFootballFixture fixture(List<HkjcMarketLine> lines) =>
        HkjcFootballFixture(
          matchId: 'm3',
          frontEndId: 'FB3',
          leagueCode: 'SP1',
          tournamentCode: 'SFL',
          tournamentName: '西班牙甲組聯賽',
          kickOffTime: DateTime.utc(2026, 8, 22),
          status: 'PREEVENT',
          homeTeam: '主',
          awayTeam: '客',
          homeTeamEnglish: 'Home',
          awayTeamEnglish: 'Away',
          cornerLines: lines,
        );
    HkjcMarketLine line(String condition, double high, double low) =>
        HkjcMarketLine(
          lineId: condition,
          condition: condition,
          line: double.parse(condition),
          main: condition == '9.5',
          status: 'AVAILABLE',
          highOdds: high,
          lowOdds: low,
        );

    final small = model.assess(
      fixture([line('9.5', 1.95, 1.85), line('10.5', 2.35, 1.60)]),
    )!;
    final large = model.assess(
      fixture([line('9.5', 3.20, 1.35), line('10.5', 2.35, 1.60)]),
    )!;

    expect(large.bestEdge, greaterThan(small.bestEdge));
    expect(
      large.recommendation!.confidence,
      greaterThan(small.recommendation?.confidence ?? 0),
    );
  });

  test('calibration shifts the model probability and gates confidence', () {
    final fixture = HkjcFootballFixture(
      matchId: 'm4',
      frontEndId: 'FB4',
      leagueCode: 'SP1',
      tournamentCode: 'SFL',
      tournamentName: '西班牙甲組聯賽',
      kickOffTime: DateTime.utc(2026, 8, 22),
      status: 'PREEVENT',
      homeTeam: '主',
      awayTeam: '客',
      cornerLines: const [
        HkjcMarketLine(
          lineId: '9.5',
          condition: '9.5',
          line: 9.5,
          main: true,
          status: 'AVAILABLE',
          highOdds: 3.20,
          lowOdds: 1.35,
        ),
        HkjcMarketLine(
          lineId: '10.5',
          condition: '10.5',
          line: 10.5,
          main: false,
          status: 'AVAILABLE',
          highOdds: 2.35,
          lowOdds: 1.60,
        ),
      ],
      homeTeamEnglish: 'Home',
      awayTeamEnglish: 'Away',
    );

    final uncalibrated = model.assess(fixture)!;
    // An unaudited model may never present itself as high confidence.
    expect(uncalibrated.recommendation!.confidence, lessThan(0.4));
    expect(uncalibrated.recommendation!.confidenceLabel, isNot('高'));

    final samples = [
      for (var index = 0; index < 120; index++)
        CalibrationSample(
          // A model that is systematically too high on the over side.
          probability: 0.7,
          outcome: index % 5 == 0,
          observedAt: DateTime.utc(2026, 1, 1).add(Duration(hours: index)),
        ),
    ];
    final calibrator = fitCalibrator(samples);
    final calibrated = HkjcCornerModel(
      calibration: MarketCalibration(
        market: '角球大細 9.5',
        calibrator: calibrator,
        report: evaluateCalibration(samples, calibrator: calibrator),
      ),
    ).assess(fixture)!;

    expect(
      calibrated.lines.first.modelHighProbability,
      lessThan(uncalibrated.lines.first.modelHighProbability),
    );
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

  test('tracks exactly the requested public HKJC tournament profiles', () {
    expect(hkjcFootballProfiles, {
      'E0': '50000051',
      'SP1': '50000100',
      'F1': '50000058',
      'I1': '50000069',
    });
    expect(HkjcFootballService.oddsTypes, contains('CHL'));
  });

  group('the published results page', () {
    Map<String, Object?> result({
      required int stageId,
      required int resultType,
      required int home,
      required int away,
    }) => {
      'homeResult': home,
      'awayResult': away,
      'ttlCornerResult': -1,
      'resultConfirmType': 5,
      'payoutConfirmed': true,
      'stageId': stageId,
      'resultType': resultType,
      'sequence': 1,
    };

    Map<String, Object?> payload(List<Map<String, Object?>> results) => {
      'data': {
        'matches': [
          {
            'id': '50073113',
            'status': 'INPLAYMATCHENDED',
            'frontEndId': 'FB3441',
            'kickOffTime': '2026-08-22T23:00:00.000+08:00',
            'homeTeam': {'name_en': 'Bilbao', 'name_ch': '畢爾包'},
            'awayTeam': {'name_en': 'Sevilla', 'name_ch': '西維爾'},
            'tournament': {'code': 'SFL', 'name_ch': '西班牙甲組聯賽'},
            'results': results,
          },
        ],
      },
    };

    final observedAt = DateTime.utc(2026, 8, 23, 2);

    test('settles a match HKJC has already dropped from its list', () {
      final results = service.parseCornerResults(
        payload([
          result(stageId: 5, resultType: 1, home: 1, away: 3),
          result(stageId: 2, resultType: 2, home: 2, away: 3),
          result(stageId: 4, resultType: 2, home: 9, away: 3),
          result(stageId: 5, resultType: 2, home: 10, away: 3),
        ]),
        observedAt: observedAt,
      );

      expect(results, hasLength(1));
      expect(results.single.matchId, '50073113');
      expect(results.single.totalCorners, 13);
      expect(results.single.kickOffTime.toUtc(), DateTime.utc(2026, 8, 22, 15));
      expect(results.single.observedAt, observedAt);
    });

    test('never reads the score as the corner count', () {
      final results = service.parseCornerResults(
        payload([
          result(stageId: 5, resultType: 1, home: 1, away: 3),
          result(stageId: 5, resultType: 4, home: 1, away: 0),
        ]),
        observedAt: observedAt,
      );

      expect(results, isEmpty);
    });

    test('waits for the paid-out stage of a match still running', () {
      final results = service.parseCornerResults(
        payload([result(stageId: 4, resultType: 2, home: 0, away: 8)]),
        observedAt: observedAt,
      );

      expect(results, isEmpty);
    });

    test('reads the whitelisted results document', () {
      expect(
        HkjcFootballService.matchResultsQuery,
        contains('matches: matchResult('),
      );
    });
  });

  group('cache standing in for a failed update', () {
    Future<HkjcFootballService> serviceWithCache(DateTime capturedAt) async {
      final directory = await Directory.systemTemp.createTemp('hkjc_cache');
      addTearDown(() => directory.delete(recursive: true));
      final snapshot = HkjcFootballSnapshot(
        capturedAt: capturedAt,
        fixtures: service.parseMatches(_payload(), const {'50071337': 'E0'}),
      );
      await File(
        '${directory.path}/fixtures.json',
      ).writeAsString(jsonEncode(snapshot.toJson()));
      // Nothing listens on this port, so the fetch always fails.
      return HkjcFootballService(
        endpoint: 'http://127.0.0.1:1/graphql',
        refreshInterval: Duration.zero,
        directory: directory,
      );
    }

    test('a recent cache is still shown, flagged as a failed update', () async {
      final stale = await serviceWithCache(
        DateTime.now().subtract(const Duration(minutes: 40)),
      );

      final loaded = await stale.load();

      expect(loaded.fixtures, isNotEmpty);
      expect(loaded.note, contains('顯示上次快取'));
    });

    test('a long-dead cache never presents fixtures as HKJC data', () async {
      final stale = await serviceWithCache(
        DateTime.now().subtract(const Duration(days: 2)),
      );

      final loaded = await stale.load();

      // HKJC drops settled matches, so an old cache would invent a market.
      expect(loaded.fixtures, isEmpty);
      expect(loaded.note, contains('不再顯示可能已完場的賽事'));
    });
  });
}
