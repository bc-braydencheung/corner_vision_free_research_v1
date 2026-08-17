import 'dart:io';
import 'dart:isolate';

import '../models/feature_ablation.dart';
import '../models/football_mobile.dart';
import 'football_mobile_engine.dart';
import 'football_store.dart';
import 'football_training_service.dart';

/// Runs and stores the purged-fold feature attribution.
///
/// The sweep costs one walk-forward per feature, so it never runs as part of a
/// refresh: it is an explicit research action, computed off the UI isolate, and
/// the stored report keeps the dataset version it was measured on so a stale
/// ranking cannot be read as a current one.
class FeatureAblationService {
  FeatureAblationService({FootballStore? store})
    : store = store ?? FootballStore();

  final FootballStore store;

  Future<FeatureAblationReport?> load() => store.loadFeatureAblation();

  Future<FeatureAblationReport> run() async {
    final dataset = await store.loadDataset();
    final directory = (await store.storageDirectory()).path;
    final report = await Isolate.run(
      () => compute(dataset, Directory(directory)),
    );
    await store.saveFeatureAblation(report);
    return report;
  }

  /// Pure computation, safe to call directly in tests.
  static FeatureAblationReport compute(
    MobileFootballDataset dataset, [
    Directory? directory,
  ]) {
    final engine = FootballMobileEngine();
    final service = FootballTrainingService(
      store: FootballStore(directory: directory),
      engine: engine,
    );
    final leagues = <FeatureAblationLeague>[];
    final skipped = <String>[];
    for (final league in dataset.leagues) {
      final rows = engine.buildTrainingRows(dataset, league);
      final scored = service.ablationOf(
        code: league.code,
        name: league.name,
        rows: rows,
      );
      if (scored == null) {
        skipped.add(league.name);
      } else {
        leagues.add(scored);
      }
    }
    return FeatureAblationReport(
      computedAt: DateTime.now(),
      datasetVersion: dataset.datasetVersion,
      leagues: leagues,
      note: skipped.isEmpty ? '' : '樣本不足未評估：${skipped.join('、')}',
    );
  }
}
