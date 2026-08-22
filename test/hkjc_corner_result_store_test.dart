import 'dart:io';

import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/models/simulated_trade.dart';
import 'package:edgewise/models/simulation_draft.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:edgewise/services/hkjc_shadow.dart';
import 'package:edgewise/services/simulation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HKJC removes a match from its list within hours of full time, so a bet keyed
/// by HKJC match id could only be settled while the finished fixture happened
/// to still be listed. Keeping every corner count that was read is what lets a
/// finished bet settle afterwards instead of waiting for the free results.
void main() {
  final kickOff = DateTime.utc(2026, 8, 22, 15);
  late Directory directory;
  late FootballStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('corner-results-');
    store = FootballStore(directory: directory);
  });

  tearDown(() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  HkjcFootballFixture fixture({int? homeCorner, int? awayCorner}) =>
      HkjcFootballFixture(
        matchId: 'hkjc-1',
        frontEndId: 'FB1',
        leagueCode: 'SP1',
        tournamentCode: 'SFL',
        tournamentName: '西班牙甲組聯賽',
        kickOffTime: kickOff,
        status: 'SECONDHALF',
        homeTeam: '畢爾包',
        awayTeam: '西維爾',
        homeTeamEnglish: 'Ath Bilbao',
        awayTeamEnglish: 'Sevilla',
        homeCorner: homeCorner,
        awayCorner: awayCorner,
      );

  SimulatedTrade trade() => SimulationDraft(
    sport: 'football',
    marketType: 'corners',
    matchId: 'hkjc-1',
    leagueCode: 'SP1',
    leagueName: '西甲',
    homeTeam: '畢爾包',
    awayTeam: '西維爾',
    startTime: kickOff,
    selectionLabel: '角球 9.5 大',
    direction: 'over',
    line: 9.5,
    odds: 2,
    modelProbability: 0.58,
    marketProbability: 0.5,
    edge: 0.16,
    confidence: 0.5,
    confidenceLabel: '中',
    recommended: true,
    marketSource: 'hkjc-chl',
    marketCapturedAt: kickOff.subtract(const Duration(hours: 2)),
  ).toTrade(stake: 100, now: kickOff.subtract(const Duration(hours: 2)));

  test(
    'a reading kept from the feed settles a fixture HKJC has dropped',
    () async {
      final live = HkjcFootballSnapshot(
        capturedAt: kickOff.add(const Duration(hours: 3)),
        fixtures: [fixture(homeCorner: 5, awayCorner: 6)],
      );
      await store.recordHkjcCornerResults(
        hkjcCornerResultsOf(
          live,
          observedAt: kickOff.add(const Duration(hours: 3)),
        ),
      );

      // A day later HKJC no longer lists the match at all.
      final gone = HkjcFootballSnapshot(
        capturedAt: kickOff,
        fixtures: const [],
      );
      final asOf = kickOff.add(const Duration(days: 1));
      final totals = {
        ...observedCornerTotals(
          await store.loadHkjcCornerResults(),
          asOf: asOf,
        ),
        ...hkjcCornerTotals(snapshot: gone, asOf: asOf),
      };

      expect(totals, {'hkjc-1': 11});
      final settled = await SimulationService().settle(
        [trade()],
        const [],
        hkjcCornerTotals: totals,
      );
      expect(settled.single.status, 'settled');
      expect(settled.single.actualTotalCorners, 11);
      expect(settled.single.profit, 100);
    },
  );

  test('a reading taken while the match runs is not settled on', () async {
    await store.recordHkjcCornerResults(
      hkjcCornerResultsOf(
        HkjcFootballSnapshot(
          capturedAt: kickOff,
          fixtures: [fixture(homeCorner: 2, awayCorner: 1)],
        ),
        observedAt: kickOff.add(const Duration(minutes: 40)),
      ),
    );

    expect(
      observedCornerTotals(
        await store.loadHkjcCornerResults(),
        asOf: kickOff.add(const Duration(days: 1)),
      ),
      isEmpty,
    );
    final trades = await SimulationService().settle(
      [trade()],
      const [],
      hkjcCornerTotals: const {},
    );
    expect(trades.single.status, 'open');
  });

  test('the latest reading of a match replaces the earlier one', () async {
    await store.recordHkjcCornerResults(
      hkjcCornerResultsOf(
        HkjcFootballSnapshot(
          capturedAt: kickOff,
          fixtures: [fixture(homeCorner: 2, awayCorner: 1)],
        ),
        observedAt: kickOff.add(const Duration(minutes: 40)),
      ),
    );
    await store.recordHkjcCornerResults(
      hkjcCornerResultsOf(
        HkjcFootballSnapshot(
          capturedAt: kickOff,
          fixtures: [fixture(homeCorner: 5, awayCorner: 6)],
        ),
        observedAt: kickOff.add(const Duration(hours: 3)),
      ),
    );

    final stored = await store.loadHkjcCornerResults();
    expect(stored, hasLength(1));
    expect(stored.single.totalCorners, 11);
  });

  test('a count corners cannot take is never stored', () async {
    await store.recordHkjcCornerResults(
      hkjcCornerResultsOf(
        HkjcFootballSnapshot(
          capturedAt: kickOff,
          fixtures: [fixture(homeCorner: 30, awayCorner: 30)],
        ),
        observedAt: kickOff.add(const Duration(hours: 3)),
      ),
    );

    expect(await store.loadHkjcCornerResults(), isEmpty);
  });

  test('a fixture without a count is not recorded as nil corners', () async {
    await store.recordHkjcCornerResults(
      hkjcCornerResultsOf(
        HkjcFootballSnapshot(capturedAt: kickOff, fixtures: [fixture()]),
        observedAt: kickOff.add(const Duration(hours: 3)),
      ),
    );

    expect(await store.loadHkjcCornerResults(), isEmpty);
  });
}
