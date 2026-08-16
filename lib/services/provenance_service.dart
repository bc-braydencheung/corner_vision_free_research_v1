import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/football_mobile.dart';
import 'calibration_service.dart';
import 'online_learning.dart';
import 'provenance.dart';

/// Persists the provenance ledger and records the app's pipeline stages into it.
///
/// Recording is idempotent per artefact: an artefact whose digest already sits
/// in the ledger is not appended again, so repeatedly opening the research page
/// cannot inflate the lineage.
class ProvenanceService {
  ProvenanceService({this.storageKey = 'edgewise_provenance_v1'});

  final String storageKey;

  Future<ProvenanceLedger> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey);
    if (encoded == null) {
      return const ProvenanceLedger();
    }
    try {
      return ProvenanceLedger.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    } on Object {
      return const ProvenanceLedger();
    }
  }

  Future<void> save(ProvenanceLedger ledger) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(storageKey, jsonEncode(ledger.toJson()));
  }

  /// Appends whatever of [dataset], [model], [calibration] and [online] is new,
  /// and returns the resulting ledger.
  Future<ProvenanceLedger> record({
    MobileFootballDataset? dataset,
    MobileFootballModel? model,
    CalibrationState? calibration,
    OnlineLearningState? online,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    var ledger = await load();
    if (dataset != null) {
      ledger = _appendUnique(
        ledger,
        id: 'dataset:${dataset.datasetVersion}',
        stage: ProvenanceStage.dataset,
        source: 'football-data.co.uk 免費歷史賽果鏡像',
        recordedAt: at,
        content: {
          'datasetVersion': dataset.datasetVersion,
          'generatedAt': dataset.generatedAt,
          'rows': dataset.rows.length,
          'leagues': dataset.leagues.map((league) => league.code).toList(),
        },
        notes: '${dataset.rows.length} 場歷史賽果，僅作訓練用',
      );
    }
    if (model != null) {
      ledger = _appendUnique(
        ledger,
        id: 'model:${model.version}',
        stage: ProvenanceStage.model,
        source: '裝置內訓練（purged walk-forward 閘門）',
        recordedAt: at,
        inputs: ['dataset:${model.datasetVersion}'],
        content: model.toJson(),
        notes: model.leagues
            .map(
              (league) =>
                  '${league.code} '
                  '${league.useModel ? '已放行' : '維持基準'}'
                  '${league.walkForward == null ? '' : ' · ${league.walkForward!.passedFolds}/${league.walkForward!.foldCount} 折'}',
            )
            .join(' · '),
      );
    }
    if (calibration != null && calibration.markets.isNotEmpty) {
      ledger = _appendUnique(
        ledger,
        id: 'calibration:${digestOf(_calibrationContent(calibration))}',
        stage: ProvenanceStage.calibration,
        source: '已結算樣本（等距回歸／溫度縮放）',
        recordedAt: at,
        content: _calibrationContent(calibration),
        notes: calibration.markets
            .map((market) => '${market.market} ${market.report.verdict}')
            .join(' · '),
      );
    }
    if (online != null && online.settledSamples > 0) {
      ledger = _appendUnique(
        ledger,
        id: 'online:${online.version}:${online.settledSamples}',
        stage: ProvenanceStage.settlement,
        source: '線上學習回放（Hedge + Page–Hinkley/CUSUM）',
        recordedAt: at,
        content: online.toJson(),
        notes:
            '${online.settledSamples} 筆已結算 · 模型權重 '
            '${(online.modelWeight * 100).round()}% · 回滾 ${online.rollbacks} 次',
      );
    }
    await save(ledger);
    return ledger;
  }

  List<Object?> _calibrationContent(CalibrationState calibration) => [
    for (final market in calibration.markets)
      {
        'market': market.market,
        'calibrator': market.calibrator.label,
        'brier': market.report.brier,
        'baselineBrier': market.report.baselineBrier,
        'ece': market.report.expectedCalibrationError,
        'samples': market.report.samples,
        'beatsBaseline': market.report.beatsBaseline,
      },
  ];

  ProvenanceLedger _appendUnique(
    ProvenanceLedger ledger, {
    required String id,
    required ProvenanceStage stage,
    required String source,
    required DateTime recordedAt,
    required Object? content,
    List<String> inputs = const [],
    String notes = '',
  }) {
    final hash = digestOf(content);
    final exists = ledger.entries.any(
      (entry) => entry.id == id && entry.contentHash == hash,
    );
    if (exists) {
      return ledger;
    }
    return ledger.append(
      id: id,
      stage: stage,
      source: source,
      content: content,
      recordedAt: recordedAt,
      inputs: inputs,
      notes: notes,
    );
  }
}
