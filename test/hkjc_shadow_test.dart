import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/hkjc_shadow.dart';
import 'package:flutter_test/flutter_test.dart';

const _lines = [
  HkjcMarketLine(
    lineId: '1',
    condition: '8.5',
    line: 8.5,
    main: false,
    status: 'AVAILABLE',
    highOdds: 1.55,
    lowOdds: 2.4,
  ),
  HkjcMarketLine(
    lineId: '2',
    condition: '9.5',
    line: 9.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 1.9,
    lowOdds: 1.9,
  ),
];

const _withoutNineFive = [
  HkjcMarketLine(
    lineId: '3',
    condition: '11.5',
    line: 11.5,
    main: true,
    status: 'AVAILABLE',
    highOdds: 2.3,
    lowOdds: 1.6,
  ),
];

HkjcFootballFixture _fixture({
  required String matchId,
  required DateTime kickOff,
  List<HkjcMarketLine> lines = _lines,
  String leagueCode = 'E0',
  String home = 'Arsenal',
  String away = 'Chelsea',
  int? homeCorner,
  int? awayCorner,
}) => HkjcFootballFixture(
  matchId: matchId,
  frontEndId: matchId,
  leagueCode: leagueCode,
  tournamentCode: leagueCode,
  tournamentName: leagueCode,
  kickOffTime: kickOff,
  status: 'PREEVENT',
  homeTeam: '主隊',
  awayTeam: '客隊',
  homeTeamEnglish: home,
  awayTeamEnglish: away,
  cornerLines: lines,
  homeCorner: homeCorner,
  awayCorner: awayCorner,
);

const _reference = {
  'E0': ShadowModelReference(version: 'nb2:2026-08-01', mae: 2.6, brier: 0.24),
};

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  test('records a priced HKJC fixture under the HKJC match id', () {
    final records = updateHkjcShadow(
      existing: const [],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'hkjc-1',
            kickOff: now.add(const Duration(hours: 6)),
          ),
        ],
      ),
      leagueNames: const {'E0': '英超'},
      references: _reference,
      asOf: now,
    );
    expect(records, hasLength(1));
    final record = records.single;
    expect(record.matchId, 'hkjc-1');
    expect(record.id, 'hkjc-1:nb2:2026-08-01');
    expect(record.leagueName, '英超');
    expect(record.homeTeam, 'Arsenal');
    expect(record.over9_5Probability, greaterThan(0));
    expect(record.over9_5Probability, lessThan(1));
    expect(record.marketOverProbability, closeTo(0.5, 0.001));
    expect(record.referenceMae, 2.6);
    expect(record.actualTotalCorners, isNull);
  });

  test('skips started fixtures and fixtures without the scored line', () {
    final records = updateHkjcShadow(
      existing: const [],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'started',
            kickOff: now.subtract(const Duration(minutes: 5)),
          ),
          _fixture(
            matchId: 'other-line',
            kickOff: now.add(const Duration(hours: 3)),
            lines: _withoutNineFive,
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now,
    );
    expect(records, isEmpty);
  });

  test('never rewrites a stored forecast for the same match and model', () {
    final first = updateHkjcShadow(
      existing: const [],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'hkjc-1',
            kickOff: now.add(const Duration(hours: 6)),
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now,
    );
    final second = updateHkjcShadow(
      existing: first,
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'hkjc-1',
            kickOff: now.add(const Duration(hours: 6)),
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now.add(const Duration(hours: 1)),
    );
    expect(second, hasLength(1));
    expect(second.single.capturedAt, first.single.capturedAt);
  });

  test('settles from the HKJC corner result once the match is over', () {
    final kickOff = now.subtract(const Duration(hours: 4));
    final stored = ShadowForecast(
      id: 'hkjc-1:nb2:2026-08-01',
      matchId: 'hkjc-1',
      leagueCode: 'E0',
      leagueName: '英超',
      homeTeam: 'Arsenal',
      awayTeam: 'Chelsea',
      matchDate: kickOff,
      capturedAt: kickOff.subtract(const Duration(hours: 2)),
      modelVersion: 'nb2:2026-08-01',
      expectedTotalCorners: 10.2,
      over9_5Probability: 0.55,
      referenceMae: 2.6,
      referenceBrier: 0.24,
    );
    final records = updateHkjcShadow(
      existing: [stored],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'hkjc-1',
            kickOff: kickOff,
            homeCorner: 6,
            awayCorner: 5,
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now,
    );
    expect(records.single.actualTotalCorners, 11);
    expect(records.single.settledAt, now);
  });

  test(
    'keeps a live match unsettled while its corner count can still move',
    () {
      final kickOff = now.subtract(const Duration(minutes: 40));
      final stored = ShadowForecast(
        id: 'hkjc-1:nb2:2026-08-01',
        matchId: 'hkjc-1',
        leagueCode: 'E0',
        leagueName: '英超',
        homeTeam: 'Arsenal',
        awayTeam: 'Chelsea',
        matchDate: kickOff,
        capturedAt: kickOff.subtract(const Duration(hours: 2)),
        modelVersion: 'nb2:2026-08-01',
        expectedTotalCorners: 10.2,
        over9_5Probability: 0.55,
        referenceMae: 2.6,
        referenceBrier: 0.24,
      );
      final records = updateHkjcShadow(
        existing: [stored],
        snapshot: HkjcFootballSnapshot(
          capturedAt: now,
          fixtures: [
            _fixture(
              matchId: 'hkjc-1',
              kickOff: kickOff,
              homeCorner: 3,
              awayCorner: 1,
            ),
          ],
        ),
        leagueNames: const {},
        references: _reference,
        asOf: now,
      );
      expect(records.single.actualTotalCorners, isNull);
    },
  );

  test(
    'settles through the free dataset result when HKJC dropped the match',
    () {
      final kickOff = now.subtract(const Duration(days: 2));
      final stored = ShadowForecast(
        id: 'hkjc-1:nb2:2026-08-01',
        matchId: 'hkjc-1',
        leagueCode: 'E0',
        leagueName: '英超',
        homeTeam: 'Atl. Madrid',
        awayTeam: 'Chelsea FC',
        matchDate: kickOff,
        capturedAt: kickOff.subtract(const Duration(hours: 2)),
        modelVersion: 'nb2:2026-08-01',
        expectedTotalCorners: 10.2,
        over9_5Probability: 0.55,
        referenceMae: 2.6,
        referenceBrier: 0.24,
      );
      final records = updateHkjcShadow(
        existing: [stored],
        snapshot: null,
        leagueNames: const {},
        references: _reference,
        asOf: now,
        settlementResults: const [
          MatchResult(
            matchId: 'E0:2026-08-18:Atl Madrid:Chelsea',
            actualTotalCorners: 8,
          ),
        ],
      );
      expect(records.single.actualTotalCorners, 8);
    },
  );

  test('drops the free-fixture record of a match HKJC also priced', () {
    final kickOff = now.add(const Duration(hours: 6));
    final dataset = ShadowForecast(
      id: 'E0:2026-08-20:Arsenal:Chelsea:nb2:2026-08-01',
      matchId: 'E0:2026-08-20:Arsenal:Chelsea',
      leagueCode: 'E0',
      leagueName: '英超',
      homeTeam: 'Arsenal',
      awayTeam: 'Chelsea',
      matchDate: kickOff,
      capturedAt: now.subtract(const Duration(hours: 1)),
      modelVersion: 'nb2:2026-08-01',
      expectedTotalCorners: 10.2,
      over9_5Probability: 0.55,
      referenceMae: 2.6,
      referenceBrier: 0.24,
    );
    final records = updateHkjcShadow(
      existing: [dataset],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [_fixture(matchId: 'hkjc-1', kickOff: kickOff)],
      ),
      leagueNames: const {'E0': '英超'},
      references: _reference,
      asOf: now,
    );
    expect(records.map((record) => record.matchId), ['hkjc-1']);
  });

  test('team keys ignore punctuation and club suffixes', () {
    expect(normaliseTeamKey('Atl. Madrid'), normaliseTeamKey('Atl Madrid'));
    expect(normaliseTeamKey('Chelsea FC'), normaliseTeamKey('Chelsea'));
    expect(normaliseTeamKey('Arsenal'), isNot(normaliseTeamKey('Chelsea')));
  });
}
