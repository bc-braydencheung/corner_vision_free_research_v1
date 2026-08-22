import 'dart:io';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/racing_mobile.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:edgewise/services/hkjc_racing_odds_service.dart';
import 'package:edgewise/services/market_timeline.dart';
import 'package:edgewise/services/odds_collector_service.dart';
import 'package:edgewise/services/racing_store.dart';
import 'package:flutter_test/flutter_test.dart';

FootballOddsSnapshot _corner({
  required DateTime capturedAt,
  required double over,
  required double under,
  double line = 9.5,
  String matchId = 'FB1',
}) => FootballOddsSnapshot(
  matchId: matchId,
  capturedAt: capturedAt,
  source: 'hkjc-chl',
  line: line,
  overOdds: over,
  underOdds: under,
);

HkjcFootballSnapshot _fixtureSnapshot({
  required DateTime kickOff,
  double? high = 1.8,
  double? low = 2.0,
  String status = 'AVAILABLE',
  String fixtureStatus = 'PREEVENT',
}) => HkjcFootballSnapshot(
  capturedAt: DateTime.now(),
  fixtures: [
    HkjcFootballFixture(
      matchId: 'FB1',
      frontEndId: 'FB0001',
      leagueCode: 'E0',
      tournamentCode: 'EPL',
      tournamentName: '英格蘭超級聯賽',
      kickOffTime: kickOff,
      status: fixtureStatus,
      homeTeam: '阿仙奴',
      awayTeam: '利物浦',
      homeTeamEnglish: 'Arsenal',
      awayTeamEnglish: 'Liverpool',
      cornerLines: [
        HkjcMarketLine(
          lineId: 'L1',
          condition: '9.5',
          line: 9.5,
          main: true,
          status: status,
          highOdds: high,
          lowOdds: low,
        ),
      ],
    ),
  ],
);

void main() {
  group('two-way market maths', () {
    test('fair probabilities remove the margin and sum to one', () {
      final fair = twoWayFairProbabilities(1.78, 1.92)!;
      expect(fair.over + fair.under, closeTo(1.0, 1e-12));
      expect(fair.over, greaterThan(fair.under));
      expect(twoWayOverround(1.78, 1.92), greaterThan(0.03));
      expect(twoWayOverround(2.0, 2.0), closeTo(0.0, 1e-12));
    });

    test('prices no two-way market can carry are refused, not clamped', () {
      // 0.5 would have been clamped to 1.01 and read as a 99% chance.
      expect(twoWayFairProbabilities(0.5, 1.9), isNull);
      expect(twoWayFairProbabilities(1.0, 1.9), isNull);
      expect(twoWayFairProbabilities(double.nan, 1.9), isNull);
      expect(twoWayFairProbabilities(double.infinity, 1.9), isNull);
      // A book summing below one is an arbitrage HKJC never offers.
      expect(twoWayFairProbabilities(2.5, 2.5), isNull);
      expect(twoWayOverround(0.5, 1.9), isNull);
    });

    test('fair odds are longer than the quoted odds', () {
      final fair = twoWayFairProbabilities(1.78, 1.92)!;
      expect(1 / fair.over, greaterThan(1.78));
      expect(1 / fair.under, greaterThan(1.92));
    });
  });

  group('corner timelines', () {
    test('separate opening, closing and drift per line', () {
      final kickOff = DateTime.utc(2026, 8, 16, 19);
      final stored = [
        _corner(
          capturedAt: kickOff.subtract(const Duration(hours: 20)),
          over: 1.9,
          under: 1.9,
        ),
        _corner(
          capturedAt: kickOff.subtract(const Duration(minutes: 5)),
          over: 1.7,
          under: 2.1,
        ),
        // A quote taken after kick-off must never be treated as the close.
        _corner(
          capturedAt: kickOff.add(const Duration(minutes: 20)),
          over: 1.4,
          under: 2.8,
        ),
        _corner(
          capturedAt: kickOff.subtract(const Duration(hours: 2)),
          over: 2.0,
          under: 1.8,
          line: 10.5,
        ),
      ];
      final timelines = cornerTimelines(stored);
      expect(timelines['FB1']!.length, 2);
      final main = timelines['FB1']!.firstWhere((entry) => entry.line == 9.5);
      expect(main.depth, 3);
      expect(main.opening!.overOdds, 1.9);
      expect(main.closing(kickOff)!.overOdds, 1.7);
      expect(main.latest!.overOdds, 1.4);
      // Over shortened from 1.9 to 1.7, so its fair probability rose.
      expect(main.drift(kickOff), greaterThan(0));
    });

    test('a single quote has no drift and no distinct close', () {
      final kickOff = DateTime.utc(2026, 8, 16, 19);
      final timeline = cornerTimelines([
        _corner(
          capturedAt: kickOff.subtract(const Duration(hours: 3)),
          over: 1.9,
          under: 1.9,
        ),
      ])['FB1']!.single;
      expect(timeline.depth, 1);
      expect(timeline.drift(kickOff), isNull);
    });

    test('quotes taken only after kick-off yield no close', () {
      final kickOff = DateTime.utc(2026, 8, 16, 19);
      final timeline = cornerTimelines([
        _corner(
          capturedAt: kickOff.add(const Duration(minutes: 10)),
          over: 1.6,
          under: 2.3,
        ),
      ])['FB1']!.single;
      expect(timeline.closing(kickOff), isNull);
    });
  });

  group('closing line value', () {
    test('beating the close is graded without any result', () {
      final report = summariseClosingLineValue([
        // Took 2.10 on a selection that closed at 1.80: beat the close.
        const ClosingLineValue(
          modelProbability: 0.58,
          takenOdds: 2.10,
          closingOdds: 1.80,
          closingFairProbability: 0.54,
        ),
        const ClosingLineValue(
          modelProbability: 0.50,
          takenOdds: 1.90,
          closingOdds: 2.05,
          closingFairProbability: 0.47,
        ),
      ]);
      expect(report.graded, 2);
      expect(report.beatClosingRate, 0.5);
      expect(report.meanAbsoluteDisagreement, greaterThan(0));
    });

    test('an empty sample reports no signal instead of a verdict', () {
      final report = summariseClosingLineValue(const []);
      expect(report.graded, 0);
      expect(report.hasSignal, isFalse);
    });
  });

  group('racing pools', () {
    test('normalising the win pool removes the takeout', () {
      final probabilities = poolProbabilities({
        'A': 2.0,
        'B': 4.0,
        'C': 5.0,
        'D': 1.0,
      });
      // 1.0 is not a payable quote and must be dropped, not treated as certain.
      expect(probabilities.containsKey('D'), isFalse);
      expect(
        probabilities.values.fold<double>(0, (sum, value) => sum + value),
        closeTo(1.0, 1e-12),
      );
      expect(probabilities['A'], greaterThan(probabilities['B']!));
    });

    test('favourite-longshot correction shifts weight to the favourite', () {
      final raw = poolProbabilities({'A': 1.5, 'B': 10.0, 'C': 40.0});
      final adjusted = favouriteLongshotAdjusted(raw);
      expect(adjusted['A'], greaterThan(raw['A']!));
      expect(adjusted['C'], lessThan(raw['C']!));
      expect(
        adjusted.values.fold<double>(0, (sum, value) => sum + value),
        closeTo(1.0, 1e-12),
      );
      expect(
        favouriteLongshotAdjusted(raw, exponent: 1.0)['A'],
        closeTo(raw['A']!, 1e-12),
      );
    });

    test('late money is the drift between the opening and closing pool', () {
      final race = DateTime.utc(2026, 8, 16, 12);
      final timeline = raceTimeline('R1', [
        RacingOddsSnapshot(
          raceId: 'R1',
          capturedAt: race.subtract(const Duration(hours: 2)),
          source: 'hkjc-win-pool',
          oddsByHorse: const {'A': 3.0, 'B': 4.0, 'C': 6.0},
        ),
        RacingOddsSnapshot(
          raceId: 'R2',
          capturedAt: race,
          source: 'hkjc-win-pool',
          oddsByHorse: const {'A': 2.0},
        ),
        RacingOddsSnapshot(
          raceId: 'R1',
          capturedAt: race.subtract(const Duration(minutes: 1)),
          source: 'hkjc-win-pool',
          oddsByHorse: const {'A': 2.0, 'B': 5.0, 'C': 7.0},
          isFinal: true,
        ),
      ]);
      expect(timeline.snapshots.length, 2);
      expect(timeline.closing!.isFinal, isTrue);
      final moves = timeline.lateMoney();
      expect(moves['A'], greaterThan(0));
      expect(moves['B'], lessThan(0));
      expect(timeline.closingProbabilities()['A'], greaterThan(0.4));
    });

    test('an empty pool yields no probabilities', () {
      expect(poolProbabilities(const {}), isEmpty);
      expect(favouriteLongshotAdjusted(const {}), isEmpty);
    });
  });

  group('scratched runners', () {
    test('are excluded from the stored pool', () {
      final runners = [
        HkjcRacingRunner(
          runnerNo: '1',
          horseCode: 'A001',
          nameChinese: '甲',
          nameEnglish: 'Alpha',
          status: 'Standby',
        ),
        HkjcRacingRunner(
          runnerNo: '2',
          horseCode: 'B002',
          nameChinese: '乙',
          nameEnglish: 'Bravo',
          status: 'Scratched',
        ),
      ];
      expect(runners.first.scratched, isFalse);
      expect(runners.last.scratched, isTrue);
      expect(runners.first.oddsKey, 'A001');
    });

    test('a race with fewer than two quotes stores no snapshot', () {
      final race = HkjcRacingRace(
        raceId: 'HK:2026-08-16:S1:1',
        raceNumber: 1,
        venueCode: 'S1',
        date: '2026-08-16',
        status: 'OPEN',
        winOdds: const {'A001': 3.5},
      );
      expect(race.snapshot(DateTime.utc(2026, 8, 16)), isNull);
    });
  });

  group('odds collector', () {
    late Directory directory;
    late FootballStore footballStore;
    late RacingStore racingStore;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('odds_collector');
      footballStore = FootballStore(directory: directory);
      racingStore = RacingStore(directory: directory);
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    OddsCollectorService collector(DateTime now) => OddsCollectorService(
      footballStore: footballStore,
      racingStore: racingStore,
      now: () => now,
    );

    test('records a corner line once and appends only when it moves', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final kickOff = now.add(const Duration(hours: 6));
      expect(
        await collector(now).recordFootball(_fixtureSnapshot(kickOff: kickOff)),
        1,
      );
      // Identical quote a minute later adds nothing.
      expect(
        await collector(
          now.add(const Duration(minutes: 1)),
        ).recordFootball(_fixtureSnapshot(kickOff: kickOff)),
        0,
      );
      expect(
        await collector(now.add(const Duration(minutes: 2))).recordFootball(
          _fixtureSnapshot(kickOff: kickOff, high: 1.7, low: 2.1),
        ),
        1,
      );
      final stored = await footballStore.loadOddsSnapshots();
      expect(stored.length, 2);
      expect(stored.first.marketId, 'L1');
      expect(stored.last.overOdds, 1.7);
      expect(stored.every((snapshot) => snapshot.line == 9.5), isTrue);
    });

    test('skips fixtures outside the horizon and unpriced lines', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final service = collector(now);
      expect(
        await service.recordFootball(
          _fixtureSnapshot(kickOff: now.add(const Duration(days: 9))),
        ),
        0,
      );
      expect(
        await service.recordFootball(
          _fixtureSnapshot(
            kickOff: now.add(const Duration(hours: 3)),
            high: null,
            low: null,
          ),
        ),
        0,
      );
      expect(await footballStore.loadOddsSnapshots(), isEmpty);
    });

    test('a started fixture is skipped instead of failing the pass', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final service = collector(now);
      // The store only accepts pre-match quotes, so an in-play price used to
      // throw and cost the pass every other fixture.
      expect(
        await service.recordFootball(
          _fixtureSnapshot(
            kickOff: now.add(const Duration(minutes: 20)),
            fixtureStatus: 'FIRSTHALF',
          ),
        ),
        0,
      );
      expect(
        await service.recordFootball(
          _fixtureSnapshot(kickOff: now.subtract(const Duration(hours: 1))),
        ),
        0,
      );
      expect(await footballStore.loadOddsSnapshots(), isEmpty);
    });

    test('a rejected quote never stops the other fixtures', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final kickOff = now.add(const Duration(hours: 5));
      final good = _fixtureSnapshot(kickOff: kickOff).fixtures.first;
      final playing = HkjcFootballFixture(
        matchId: 'FB2',
        frontEndId: 'FB0002',
        leagueCode: 'E0',
        tournamentCode: 'EPL',
        tournamentName: '英格蘭超級聯賽',
        kickOffTime: now.add(const Duration(minutes: 10)),
        status: 'SECONDHALF',
        homeTeam: '車路士',
        awayTeam: '熱刺',
        homeTeamEnglish: 'Chelsea',
        awayTeamEnglish: 'Tottenham',
        cornerLines: good.cornerLines,
      );

      expect(
        await collector(now).recordFootball(
          HkjcFootballSnapshot(capturedAt: now, fixtures: [playing, good]),
        ),
        1,
      );
      final stored = await footballStore.loadOddsSnapshots();
      expect(stored.map((snapshot) => snapshot.matchId), ['FB1']);
      expect(stored.single.inPlay, isFalse);
    });

    test('records the win pool of every open race', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final postTime = now.add(const Duration(hours: 2));
      final meeting = HkjcRacingMeeting(
        date: '2026-08-16',
        venueCode: 'S1',
        status: 'OPEN',
        races: [
          HkjcRacingRace(
            raceId: 'HK:2026-08-16:S1:1',
            raceNumber: 1,
            venueCode: 'S1',
            date: '2026-08-16',
            status: 'OPEN',
            postTime: postTime,
            winOdds: const {'A001': 3.5, 'B002': 4.5},
          ),
          HkjcRacingRace(
            raceId: 'HK:2026-08-16:S1:2',
            raceNumber: 2,
            venueCode: 'S1',
            date: '2026-08-16',
            status: 'OPEN',
            postTime: postTime,
            winOdds: const {'C003': 2.5},
          ),
        ],
      );
      expect(await collector(now).recordRacing(meeting), 1);
      expect(
        await collector(
          now.add(const Duration(minutes: 1)),
        ).recordRacing(meeting),
        0,
      );
      final stored = await racingStore.loadOddsSnapshots();
      expect(stored.single.raceId, 'HK:2026-08-16:S1:1');
      expect(stored.single.oddsByHorse, {'A001': 3.5, 'B002': 4.5});
    });

    test('grades displayed picks against the closing quote', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      final service = collector(now);
      final kickOff = now.add(const Duration(hours: 3));
      final graded = service.gradeAgainstClosing(
        stored: [
          _corner(
            capturedAt: now.subtract(const Duration(hours: 5)),
            over: 2.1,
            under: 1.75,
          ),
          _corner(
            capturedAt: kickOff.subtract(const Duration(minutes: 3)),
            over: 1.8,
            under: 2.0,
          ),
        ],
        predictions: [
          (
            matchId: 'FB1',
            line: 9.5,
            over: true,
            modelProbability: 0.57,
            takenOdds: 2.1,
            kickOff: kickOff,
          ),
          // No stored timeline for this fixture, so it cannot be graded.
          (
            matchId: 'FB9',
            line: 9.5,
            over: true,
            modelProbability: 0.5,
            takenOdds: 2.0,
            kickOff: kickOff,
          ),
        ],
      );
      expect(graded.length, 1);
      expect(graded.single.beatClosing, isTrue);
      expect(summariseClosingLineValue(graded).beatClosingRate, 1.0);
    });
  });
}
