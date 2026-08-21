import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/shadow_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('requires 30 settled shadow forecasts before drift decision', () {
    final service = ShadowService();
    final health = service.evaluate(
      List.generate(29, (index) => _record(index, actual: 16)),
    );

    expect(health.status, 'insufficient');
    expect(health.settledForecasts, 29);
  });

  test('stops trading after severe prospective drift', () {
    final service = ShadowService();
    final health = service.evaluate(
      List.generate(30, (index) => _record(index, actual: 16)),
    );

    expect(health.status, 'stop');
    expect(health.suspendTrading, isTrue);
    expect(health.mae, 6);
  });

  test(
    'a record without a 9.5 line survives storage with its shown pick',
    () async {
      final service = ShadowService();
      final stored = _record(
        0,
        probability: null,
        pick: const ShadowPick(
          line: 10.5,
          direction: 'high',
          odds: 2.1,
          modelProbability: 0.56,
          marketProbability: 0.5,
          edge: 0.176,
          recommended: true,
        ),
      );
      await service.save([stored]);

      final loaded = (await service.load()).single;

      expect(loaded.over9_5Probability, isNull);
      expect(loaded.homeTeamChinese, '甲隊');
      expect(loaded.pick!.line, 10.5);
      expect(loaded.pick!.odds, 2.1);
      expect(loaded.pick!.recommended, isTrue);
    },
  );

  test('keeps only latest 5000 immutable shadow records', () async {
    final service = ShadowService();
    await service.save(List.generate(5002, (index) => _record(index)));

    final loaded = await service.load();

    expect(loaded, hasLength(5000));
    expect(loaded.first.id, 'shadow-2');
    expect(loaded.last.id, 'shadow-5001');
  });
}

ShadowForecast _record(
  int index, {
  int? actual,
  double? probability = 0.5,
  ShadowPick? pick,
}) {
  final captured = DateTime.utc(2026, 1, 1).add(Duration(minutes: index));
  return ShadowForecast(
    id: 'shadow-$index',
    matchId: 'match-$index',
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: 'Alpha',
    awayTeam: 'Beta',
    homeTeamChinese: '甲隊',
    awayTeamChinese: '乙隊',
    matchDate: captured.add(const Duration(days: 1)),
    capturedAt: captured,
    modelVersion: 'test:2025-12-31',
    expectedTotalCorners: 10,
    over9_5Probability: probability,
    pick: pick,
    referenceMae: 1,
    referenceBrier: 0.1,
    actualTotalCorners: actual,
    settledAt: actual == null ? null : captured.add(const Duration(days: 2)),
  );
}
