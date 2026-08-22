import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/models/simulated_trade.dart';
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

  test('skips started fixtures', () {
    final records = updateHkjcShadow(
      existing: const [],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'started',
            kickOff: now.subtract(const Duration(minutes: 5)),
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now,
    );
    expect(records, isEmpty);
  });

  test('records the shown side of a fixture HKJC never quoted at 9.5', () {
    final records = updateHkjcShadow(
      existing: const [],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
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
    final record = records.single;
    expect(record.over9_5Probability, isNull);
    final pick = record.pick!;
    expect(pick.line, 11.5);
    expect(pick.odds, anyOf(2.3, 1.6));
    expect(pick.marketProbability, greaterThan(0));
    expect(pick.marketProbability, lessThan(1));
  });

  test('stores the HKJC Chinese club names beside the dataset ones', () {
    final record = updateHkjcShadow(
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
    ).single;
    expect(record.homeTeam, 'Arsenal');
    expect(record.homeTeamChinese, '主隊');
    expect(record.awayTeamChinese, '客隊');
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

  test('an observation that later clears the gate becomes the record', () {
    final kickOff = now.add(const Duration(hours: 6));
    final first = updateHkjcShadow(
      existing: const [],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [_fixture(matchId: 'hkjc-1', kickOff: kickOff)],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now,
    );
    expect(first.single.pick!.recommended, isFalse);

    final later = now.add(const Duration(hours: 1));
    final second = updateHkjcShadow(
      existing: first,
      snapshot: HkjcFootballSnapshot(
        capturedAt: later,
        fixtures: [
          _fixture(
            matchId: 'hkjc-1',
            kickOff: kickOff,
            // The 9.5 price now disagrees with the 8.5 one the model fits
            // its mean on, which is what an edge looks like.
            lines: const [
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
                highOdds: 4,
                lowOdds: 1.3,
              ),
            ],
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: later,
    );
    expect(second, hasLength(1));
    final pick = second.single.pick!;
    expect(pick.recommended, isTrue);
    expect(pick.odds, 4);
    expect(second.single.capturedAt, later);

    // Once the recommendation is on record it stays, at the price it carried.
    final third = updateHkjcShadow(
      existing: second,
      snapshot: HkjcFootballSnapshot(
        capturedAt: later,
        fixtures: [_fixture(matchId: 'hkjc-1', kickOff: kickOff)],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now.add(const Duration(hours: 2)),
    );
    expect(third.single.pick!.odds, 4);
    expect(third.single.capturedAt, later);
  });

  group('a simulated bet restores the recommendation it was placed on', () {
    final kickOff = now.subtract(const Duration(hours: 4));
    final observation = ShadowForecast(
      id: 'hkjc-1:nb2:2026-08-01',
      matchId: 'hkjc-1',
      leagueCode: 'SP1',
      leagueName: '西甲',
      homeTeam: 'Athletic Bilbao',
      awayTeam: 'Sevilla',
      matchDate: kickOff,
      capturedAt: kickOff.subtract(const Duration(hours: 6)),
      modelVersion: 'nb2:2026-08-01',
      expectedTotalCorners: 9.8,
      over9_5Probability: 0.52,
      referenceMae: 2.6,
      referenceBrier: 0.24,
      pick: const ShadowPick(
        line: 9.5,
        direction: 'low',
        odds: 1.63,
        modelProbability: 0.52,
        marketProbability: 0.55,
        edge: -0.0076,
        recommended: false,
      ),
    );
    SimulatedTrade bet({
      String matchId = 'hkjc-1',
      String sport = 'football',
      String marketType = 'corners',
      bool recommended = true,
      DateTime? createdAt,
    }) => SimulatedTrade(
      id: 'bet-1',
      matchId: matchId,
      leagueCode: 'SP1',
      leagueName: '西甲',
      homeTeam: '畢爾包',
      awayTeam: '西維爾',
      matchDate: kickOff,
      createdAt: createdAt ?? kickOff.subtract(const Duration(hours: 1)),
      direction: 'under',
      line: 9.5,
      odds: 1.72,
      stake: 50,
      modelWinProbability: 0.63,
      modelPushProbability: 0.08,
      expectedValue: 0.0836,
      confidence: '中',
      status: 'open',
      actualTotalCorners: null,
      profit: null,
      sport: sport,
      marketType: marketType,
      recommended: recommended,
      marketProbability: 0.58,
    );

    test('at the line and price the bet carried', () {
      final record = withSimulatedPicks([observation], [bet()]).single;
      final pick = record.pick!;
      expect(pick.recommended, isTrue);
      expect(pick.direction, 'low');
      expect(pick.line, 9.5);
      expect(pick.odds, 1.72);
      expect(pick.edge, closeTo(0.0836, 1e-9));
      expect(pick.modelProbability, 0.63);
      expect(record.capturedAt, kickOff.subtract(const Duration(hours: 1)));
      expect(record.actualTotalCorners, isNull);
    });

    test('never through a bet of another match', () {
      final records = withSimulatedPicks(
        [observation],
        [bet(matchId: 'hkjc-2')],
      );
      final kept = records.firstWhere((r) => r.matchId == 'hkjc-1');
      expect(kept.pick!.recommended, isFalse);
      expect(kept.pick!.odds, 1.63);
    });

    test('never through a bet of another sport or market', () {
      for (final other in [
        bet(sport: 'racing', marketType: 'win'),
        bet(marketType: 'goals'),
        bet(recommended: false),
        bet(createdAt: kickOff.add(const Duration(minutes: 30))),
      ]) {
        final record = withSimulatedPicks([observation], [other]).single;
        expect(record.pick!.recommended, isFalse);
        expect(record.pick!.odds, 1.63);
      }
    });

    test('rebuilds the record the ledger no longer holds', () {
      final records = withSimulatedPicks(const [], [bet()]);
      final record = records.single;
      expect(record.matchId, 'hkjc-1');
      expect(record.leagueCode, 'SP1');
      expect(record.homeTeamChinese, '畢爾包');
      expect(record.awayTeamChinese, '西維爾');
      expect(record.matchDate, kickOff);
      expect(record.capturedAt, kickOff.subtract(const Duration(hours: 1)));
      expect(record.pick!.recommended, isTrue);
      expect(record.pick!.line, 9.5);
      expect(record.pick!.direction, 'low');
      expect(record.pick!.odds, 1.72);
      expect(record.pick!.marketProbability, 0.58);
      expect(record.pick!.edge, closeTo(0.0836, 1e-9));
      // Nothing about the corner distribution is invented for a rebuilt row.
      expect(record.over9_5Probability, isNull);
    });

    test('rebuilds nothing from a bet that carries no recommendation', () {
      for (final other in [
        bet(sport: 'racing', marketType: 'win'),
        bet(marketType: 'goals'),
        bet(recommended: false),
        bet(createdAt: kickOff.add(const Duration(minutes: 30))),
      ]) {
        expect(withSimulatedPicks(const [], [other]), isEmpty);
      }
    });

    test('settles a rebuilt record from the stored HKJC result', () {
      final records = updateHkjcShadow(
        existing: const [],
        // The finished match is long gone from the HKJC fixture list.
        snapshot: HkjcFootballSnapshot(capturedAt: now, fixtures: const []),
        leagueNames: const {},
        references: _reference,
        asOf: now,
        observedResults: [
          HkjcCornerResult(
            matchId: 'hkjc-1',
            kickOffTime: kickOff,
            homeCorner: 10,
            awayCorner: 3,
            status: 'INPLAYMATCHENDED',
            observedAt: now,
          ),
        ],
        trades: [bet()],
      );
      final record = records.single;
      expect(record.pick!.recommended, isTrue);
      expect(record.actualTotalCorners, 13);
      expect(record.settledAt, isNotNull);
    });
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

  test('settles from a kept reading after HKJC drops the fixture', () {
    final kickOff = now.subtract(const Duration(days: 1));
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
      // HKJC removes a settled match from its list, so the count only exists
      // in the reading taken while it was still there.
      snapshot: HkjcFootballSnapshot(capturedAt: now, fixtures: const []),
      leagueNames: const {},
      references: _reference,
      asOf: now,
      observedResults: [
        HkjcCornerResult(
          matchId: 'hkjc-1',
          kickOffTime: kickOff,
          homeCorner: 4,
          awayCorner: 3,
          status: 'SECONDHALF',
          observedAt: kickOff.add(const Duration(hours: 3)),
        ),
      ],
    );
    expect(records.single.actualTotalCorners, 7);
  });

  test('ignores a reading taken before the match could be over', () {
    final kickOff = now.subtract(const Duration(days: 1));
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
      snapshot: HkjcFootballSnapshot(capturedAt: now, fixtures: const []),
      leagueNames: const {},
      references: _reference,
      asOf: now,
      observedResults: [
        HkjcCornerResult(
          matchId: 'hkjc-1',
          kickOffTime: kickOff,
          homeCorner: 1,
          awayCorner: 2,
          status: 'FIRSTHALF',
          observedAt: kickOff.add(const Duration(minutes: 30)),
        ),
      ],
    );
    expect(records.single.actualTotalCorners, isNull);
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

  test('a stored forecast keeps the probability before every market step', () {
    final record = updateHkjcShadow(
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
    ).single;

    // Without a fitted calibrator the raw and calibrated stages agree, but both
    // must be present: the calibrator is refitted on the raw stage, so a record
    // that only kept the displayed number would train it on its own output.
    expect(record.uncalibratedOver9_5Probability, isNotNull);
    expect(record.calibratedOver9_5Probability, isNotNull);
    expect(
      record.uncalibratedOver9_5Probability,
      closeTo(record.calibratedOver9_5Probability!, 1e-12),
    );
    expect(record.uncalibratedOver9_5Probability, greaterThan(0));
    expect(record.uncalibratedOver9_5Probability, lessThan(1));
  });

  test('bridge keys separate fixtures the free feed could confuse', () {
    final day = DateTime.utc(2026, 8, 20, 19);
    String key({
      String league = 'E0',
      String home = 'Arsenal',
      String away = 'Chelsea',
      DateTime? date,
    }) => shadowBridgeKey(
      leagueCode: league,
      date: date ?? day,
      homeTeam: home,
      awayTeam: away,
    );

    // Two fixtures of the same league on the same day.
    expect(key(), isNot(key(home: 'Everton', away: 'Fulham')));
    // The same two clubs, reversed: home advantage is a different fixture.
    expect(key(), isNot(key(home: 'Chelsea', away: 'Arsenal')));
    // Clubs with the same name in different competitions.
    expect(key(), isNot(key(league: 'I1')));
    // Two capture instants inside one UTC day are one fixture.
    expect(key(date: DateTime.utc(2026, 8, 20, 1)), key());
    // A local kick-off crossing midnight UTC is a different calendar day, which
    // the settlement lookup handles by widening its window, not by pairing.
    expect(key(date: DateTime.utc(2026, 8, 21, 1)), isNot(key()));
  });

  test('a free result filed a day apart still settles the fixture', () {
    final kickOff = DateTime.utc(2026, 8, 18, 23, 30);
    final stored = ShadowForecast(
      id: 'hkjc-1:nb2:2026-08-01',
      matchId: 'hkjc-1',
      leagueCode: 'SP1',
      leagueName: '西甲',
      homeTeam: 'Sevilla',
      awayTeam: 'Valencia',
      matchDate: kickOff,
      capturedAt: kickOff.subtract(const Duration(hours: 5)),
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
          matchId: 'SP1:2026-08-19:Sevilla:Valencia',
          actualTotalCorners: 9,
        ),
      ],
    );
    expect(records.single.actualTotalCorners, 9);
  });

  test('impossible corner counts are refused by both settlement paths', () {
    final kickOff = now.subtract(const Duration(days: 2));
    ShadowForecast stored(String id, String matchId) => ShadowForecast(
      id: id,
      matchId: matchId,
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
      existing: [stored('hkjc-1:nb2:2026-08-01', 'hkjc-1')],
      snapshot: HkjcFootballSnapshot(
        capturedAt: now,
        fixtures: [
          _fixture(
            matchId: 'hkjc-1',
            kickOff: kickOff,
            homeCorner: -1,
            awayCorner: 4,
          ),
        ],
      ),
      leagueNames: const {},
      references: _reference,
      asOf: now,
      settlementResults: const [
        MatchResult(
          matchId: 'E0:2026-08-18:Arsenal:Chelsea',
          actualTotalCorners: 400,
        ),
      ],
    );
    expect(records.single.actualTotalCorners, isNull);
  });
}
