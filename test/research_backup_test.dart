import 'dart:convert';

import 'package:edgewise/models/simulated_trade.dart';
import 'package:edgewise/services/football_store.dart';
import 'package:edgewise/services/research_backup_service.dart';
import 'package:edgewise/services/racing_store.dart';
import 'package:edgewise/services/shadow_service.dart';
import 'package:edgewise/services/simulation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('exports a complete research report and restores records', () async {
    final service = ResearchBackupService(
      footballStore: _FakeFootballStore(),
      shadowService: ShadowService(),
      simulationService: SimulationService(),
      racingStore: _FakeRacingStore(),
    );
    final trade = _trade('trade-1');

    final encoded = await service.export([trade]);
    final decoded = (jsonDecode(encoded) as Map).cast<String, Object?>();
    final report = (decoded['researchReport'] as Map).cast<String, Object?>();
    final imported = await service.import(encoded);

    expect(report['settledTrades'], 1);
    expect(report['bootstrap90'], isA<List<Object?>>());
    expect(report['bootstrap95'], isA<List<Object?>>());
    expect(report['calibration'], isA<List<Object?>>());
    expect(report['seasonSummaries'], isA<List<Object?>>());
    expect(imported.trades.single.id, 'trade-1');
  });

  test('rejects duplicate immutable trade ids during restore', () async {
    final service = ResearchBackupService(
      footballStore: _FakeFootballStore(),
      shadowService: ShadowService(),
      simulationService: SimulationService(),
      racingStore: _FakeRacingStore(),
    );
    await expectLater(
      service.import(
        await service.export([_trade('duplicate'), _trade('duplicate')]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a backup whose checksum was changed', () async {
    final service = ResearchBackupService(
      footballStore: _FakeFootballStore(),
      shadowService: ShadowService(),
      simulationService: SimulationService(),
      racingStore: _FakeRacingStore(),
    );
    final encoded = await service.export([_trade('trade-1')]);
    final decoded = (jsonDecode(encoded) as Map).cast<String, Object?>();
    decoded['app'] = 'tampered';

    await expectLater(
      service.import(jsonEncode(decoded)),
      throwsA(isA<FormatException>()),
    );
  });
}

class _FakeFootballStore extends FootballStore {
  @override
  Future<Map<String, Object?>> exportResearchSnapshots() async => {
    'schemaVersion': 1,
    'oddsSnapshots': <Object?>[],
    'weatherSnapshots': <Object?>[],
  };

  @override
  Future<(int, int)> importResearchSnapshots(
    Map<String, Object?> payload,
  ) async => (0, 0);

  @override
  Future<Map<String, Object?>> exportRecoveryState() async => {
    'schemaVersion': 1,
    'activeModel': null,
    'trainingJob': null,
  };

  @override
  Future<(bool, bool)> importRecoveryState(
    Map<String, Object?> payload,
  ) async => (false, false);
}

class _FakeRacingStore extends RacingStore {
  @override
  Future<Map<String, Object?>> exportResearchSnapshots() async => {
    'schemaVersion': 1,
    'oddsSnapshots': <Object?>[],
  };

  @override
  Future<int> importResearchSnapshots(Map<String, Object?> payload) async => 0;

  @override
  Future<Map<String, Object?>> exportRecoveryState() async => {
    'schemaVersion': 1,
    'activeModel': null,
    'trainingJob': null,
  };

  @override
  Future<(bool, bool)> importRecoveryState(
    Map<String, Object?> payload,
  ) async => (false, false);
}

SimulatedTrade _trade(String id) {
  return SimulatedTrade(
    id: id,
    matchId: 'E0:2026-01-01:Alpha:Beta',
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: 'Alpha',
    awayTeam: 'Beta',
    matchDate: DateTime.utc(2026, 1, 1),
    createdAt: DateTime.utc(2025, 12, 31),
    direction: 'over',
    line: 9.5,
    odds: 2,
    stake: 5,
    modelWinProbability: 0.55,
    modelPushProbability: 0,
    expectedValue: 0.1,
    confidence: 'high',
    status: 'settled',
    actualTotalCorners: 11,
    profit: 5,
  );
}
