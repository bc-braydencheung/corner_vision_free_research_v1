import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/forecast_data.dart';
import '../models/shadow_forecast.dart';

class ShadowLoad {
  const ShadowLoad({required this.records, required this.health});

  final List<ShadowForecast> records;
  final ShadowHealth health;
}

class ShadowService {
  static const _storageKey = 'edgewise_shadow_forecasts_v1';

  Future<ShadowLoad> update(ForecastData data) async {
    final records = await load();
    final byId = {for (final record in records) record.id: record};
    final results = {
      for (final result in data.settlementResults)
        result.matchId: result.actualTotalCorners,
    };
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final league in data.leagues) {
      final modelVersion =
          '${league.model.selectedCandidate}:${league.model.trainedThrough}';
      for (final prediction in league.forecasts) {
        if (prediction.mode != 'forecast' ||
            prediction.actualTotalCorners != null ||
            !prediction.date.toUtc().isAfter(now)) {
          continue;
        }
        final id = '${prediction.matchId}:$modelVersion';
        if (byId.containsKey(id)) {
          continue;
        }
        byId[id] = ShadowForecast(
          id: id,
          matchId: prediction.matchId,
          leagueCode: league.code,
          leagueName: league.name,
          homeTeam: prediction.homeTeam,
          awayTeam: prediction.awayTeam,
          matchDate: prediction.date,
          capturedAt: now,
          modelVersion: modelVersion,
          expectedTotalCorners: prediction.expectedTotalCorners,
          over9_5Probability: prediction.primaryMarket.overProbability,
          referenceMae: league.model.maeTotalCorners,
          referenceBrier: league.model.brierOver9_5,
        );
        changed = true;
      }
    }
    for (final entry in byId.entries.toList()) {
      final actual = results[entry.value.matchId];
      if (actual != null && entry.value.actualTotalCorners == null) {
        byId[entry.key] = entry.value.settle(actual, now);
        changed = true;
      }
    }
    final updated = byId.values.toList()
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    if (updated.length > 5000) {
      updated.removeRange(0, updated.length - 5000);
      changed = true;
    }
    if (changed) {
      await save(updated);
    }
    return ShadowLoad(records: updated, health: evaluate(updated));
  }

  Future<List<ShadowForecast>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return [];
    }
    final payload = (jsonDecode(encoded) as Map).cast<String, Object?>();
    return (payload['records'] as List<Object?>? ?? const [])
        .map(
          (value) =>
              ShadowForecast.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList();
  }

  Future<void> save(List<ShadowForecast> records) async {
    final ids = <String>{};
    if (records.any(
      (record) =>
          record.id.isEmpty ||
          !record.expectedTotalCorners.isFinite ||
          record.expectedTotalCorners < 0 ||
          !record.over9_5Probability.isFinite ||
          record.over9_5Probability < 0 ||
          record.over9_5Probability > 1 ||
          !record.capturedAt.toUtc().isBefore(record.matchDate.toUtc()) ||
          ((record.actualTotalCorners == null) != (record.settledAt == null)) ||
          (record.settledAt != null &&
              record.settledAt!.toUtc().isBefore(record.matchDate.toUtc())) ||
          !ids.add(record.id),
    )) {
      throw const FormatException('Invalid shadow forecast records.');
    }
    final ordered = [...records]
      ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
    final retained = ordered.length > 5000
        ? ordered.sublist(ordered.length - 5000)
        : ordered;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode({
        'schemaVersion': 1,
        'records': retained.map((record) => record.toJson()).toList(),
      }),
    );
  }

  ShadowHealth evaluate(List<ShadowForecast> records) {
    final settled =
        records.where((record) => record.actualTotalCorners != null).toList()
          ..sort(
            (left, right) => (left.settledAt ?? left.matchDate).compareTo(
              right.settledAt ?? right.matchDate,
            ),
          );
    final recent = settled.length > 100
        ? settled.sublist(settled.length - 100)
        : settled;
    if (recent.isEmpty) {
      return ShadowHealth(
        status: 'insufficient',
        message: '已保存前瞻預測，等待賽果後自動評估漂移。',
        totalForecasts: records.length,
        settledForecasts: 0,
        openForecasts: records.length,
        mae: 0,
        brierOver9_5: 0,
        referenceMae: 0,
        referenceBrier: 0,
      );
    }
    final mae =
        recent.fold<double>(
          0,
          (sum, record) =>
              sum +
              (record.expectedTotalCorners - record.actualTotalCorners!).abs(),
        ) /
        recent.length;
    final brier =
        recent.fold<double>(0, (sum, record) {
          final actual = record.actualTotalCorners! > 9.5 ? 1.0 : 0.0;
          return sum + pow(record.over9_5Probability - actual, 2);
        }) /
        recent.length;
    final referenceMae =
        recent.fold<double>(0, (sum, record) => sum + record.referenceMae) /
        recent.length;
    final referenceBrier =
        recent.fold<double>(0, (sum, record) => sum + record.referenceBrier) /
        recent.length;
    var status = 'insufficient';
    var message = '已結算 ${recent.length} 場；至少30場後才判斷前瞻漂移。';
    if (recent.length >= 30) {
      if ((referenceMae > 0 && mae > referenceMae * 1.35) ||
          (referenceBrier > 0 && brier > referenceBrier + 0.06)) {
        status = 'stop';
        message = '前瞻誤差明顯惡化，已建議停止新增模擬交易並重新驗證。';
      } else if ((referenceMae > 0 && mae > referenceMae * 1.15) ||
          (referenceBrier > 0 && brier > referenceBrier + 0.03)) {
        status = 'watch';
        message = '前瞻誤差高於候選外基準，模型需要密切監察。';
      } else {
        status = 'stable';
        message = '前瞻誤差暫時維持在候選外基準範圍內。';
      }
    }
    return ShadowHealth(
      status: status,
      message: message,
      totalForecasts: records.length,
      settledForecasts: settled.length,
      openForecasts: records.length - settled.length,
      mae: mae,
      brierOver9_5: brier,
      referenceMae: referenceMae,
      referenceBrier: referenceBrier,
    );
  }
}
