import 'dart:convert';
import 'dart:math';

import '../models/shadow_forecast.dart';
import '../models/simulated_trade.dart';
import '../models/football_mobile.dart';
import '../models/racing_mobile.dart';
import 'football_store.dart';
import 'racing_store.dart';
import 'shadow_service.dart';
import 'simulation_service.dart';

class BackupImportResult {
  const BackupImportResult({
    required this.trades,
    required this.oddsImported,
    required this.weatherImported,
    required this.racingOddsImported,
    required this.shadowForecasts,
    required this.modelsRestored,
    required this.checkpointsRestored,
  });

  final List<SimulatedTrade> trades;
  final int oddsImported;
  final int weatherImported;
  final int racingOddsImported;
  final int shadowForecasts;
  final int modelsRestored;
  final int checkpointsRestored;
}

class ResearchBackupService {
  ResearchBackupService({
    FootballStore? footballStore,
    ShadowService? shadowService,
    SimulationService? simulationService,
    RacingStore? racingStore,
  }) : footballStore = footballStore ?? FootballStore(),
       shadowService = shadowService ?? ShadowService(),
       simulationService = simulationService ?? SimulationService(),
       racingStore = racingStore ?? RacingStore();

  final FootballStore footballStore;
  final ShadowService shadowService;
  final SimulationService simulationService;
  final RacingStore racingStore;

  Future<String> report(List<SimulatedTrade> trades) async {
    final shadow = await shadowService.load();
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(_researchReport(trades, shadow));
  }

  Future<String> export(List<SimulatedTrade> trades) async {
    final snapshots = await footballStore.exportResearchSnapshots();
    final shadow = await shadowService.load();
    final footballRecovery = await footballStore.exportRecoveryState();
    final racingRecovery = await racingStore.exportRecoveryState();
    final racingSnapshots = await racingStore.exportResearchSnapshots();
    final researchReport = _researchReport(trades, shadow);
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'app': 'EdgeWise',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'simulatedTrades': trades.map((trade) => trade.toJson()).toList(),
      'footballResearchSnapshots': snapshots,
      'shadowForecasts': shadow.map((record) => record.toJson()).toList(),
      'footballRecovery': footballRecovery,
      'racingRecovery': racingRecovery,
      'racingResearchSnapshots': racingSnapshots,
      'researchReport': researchReport,
    };
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({...payload, 'checksum': _checksum(jsonEncode(payload))});
  }

  Map<String, Object?> _researchReport(
    List<SimulatedTrade> trades,
    List<ShadowForecast> shadow,
  ) {
    final settled = trades.where((trade) => trade.status == 'settled').toList();
    final turnover = settled.fold<double>(0, (sum, trade) => sum + trade.stake);
    final profit = settled.fold<double>(
      0,
      (sum, trade) => sum + (trade.profit ?? 0),
    );
    final risk = simulationService.riskSummary(trades);
    final shadowHealth = shadowService.evaluate(shadow);
    final bootstrap = _bootstrapRoi(settled);
    return {
      'label': '統計研究／虛擬模擬，不保證盈利、準確或結果',
      'settledTrades': settled.length,
      'openTrades': trades.length - settled.length,
      'turnover': turnover,
      'profit': profit,
      'roi': turnover == 0 ? 0 : profit / turnover,
      'maximumDrawdown': risk.maximumDrawdown,
      'bootstrap90': bootstrap.$1,
      'bootstrap95': bootstrap.$2,
      'shadowSettled': shadowHealth.settledForecasts,
      'shadowMae': shadowHealth.mae,
      'shadowBrierOver9_5': shadowHealth.brierOver9_5,
      'shadowStatus': shadowHealth.status,
      'sportSummaries': _groupSummaries(settled, (trade) => trade.sport),
      'seasonSummaries': _groupSummaries(
        settled,
        (trade) => _seasonLabel(trade.matchDate),
      ),
      'strategySummaries': _groupSummaries(
        settled,
        (trade) => trade.stakeStrategy,
      ),
      'calibration': _calibration(settled),
      'trades': trades.map((trade) => trade.toJson()).toList(),
      'benchmark': '沒有真實角球市場價格時，固定盤口結果只屬研究代理。',
      'dataLimitations': [
        'Betfair Basic檔由使用者私人匯入；未匯入時交易閘門停用。',
        '最終賠率不可冒充固定時間賽前快照或可信CLV。',
        '注碼限制只能控制風險，不能令負期望值策略變成正期望值。',
      ],
    };
  }

  static List<Map<String, Object?>> _groupSummaries(
    List<SimulatedTrade> trades,
    String Function(SimulatedTrade) keyFor,
  ) {
    final groups = <String, List<SimulatedTrade>>{};
    for (final trade in trades) {
      groups.putIfAbsent(keyFor(trade), () => []).add(trade);
    }
    return groups.entries.map((entry) {
      final turnover = entry.value.fold<double>(
        0,
        (sum, trade) => sum + trade.stake,
      );
      final profit = entry.value.fold<double>(
        0,
        (sum, trade) => sum + (trade.profit ?? 0),
      );
      return {
        'group': entry.key,
        'trades': entry.value.length,
        'turnover': turnover,
        'profit': profit,
        'roi': turnover == 0 ? 0 : profit / turnover,
      };
    }).toList()..sort(
      (left, right) =>
          (left['group'] as String).compareTo(right['group'] as String),
    );
  }

  static List<Map<String, Object?>> _calibration(List<SimulatedTrade> trades) {
    final buckets = <int, List<SimulatedTrade>>{};
    for (final trade in trades.where((trade) => trade.profit != 0)) {
      final bucket = (trade.modelWinProbability * 10)
          .floor()
          .clamp(0, 9)
          .toInt();
      buckets.putIfAbsent(bucket, () => []).add(trade);
    }
    return buckets.entries.map((entry) {
      final predicted =
          entry.value.fold<double>(
            0,
            (sum, trade) => sum + trade.modelWinProbability,
          ) /
          entry.value.length;
      final observed =
          entry.value.where((trade) => (trade.profit ?? 0) > 0).length /
          entry.value.length;
      return {
        'bucket': '${entry.key * 10}-${(entry.key + 1) * 10}%',
        'sample': entry.value.length,
        'predicted': predicted,
        'observed': observed,
      };
    }).toList()..sort(
      (left, right) =>
          (left['bucket'] as String).compareTo(right['bucket'] as String),
    );
  }

  static String _seasonLabel(DateTime value) {
    final utc = value.toUtc();
    final start = utc.month >= 7 ? utc.year : utc.year - 1;
    return '$start/${(start + 1).toString().substring(2)}';
  }

  static (List<double>, List<double>) _bootstrapRoi(
    List<SimulatedTrade> settled,
  ) {
    if (settled.isEmpty) {
      return ([0, 0], [0, 0]);
    }
    final meetings = <String, List<SimulatedTrade>>{};
    for (final trade in settled) {
      final date = trade.matchDate.toUtc();
      final key = '${date.year}-${date.month}-${date.day}-${trade.sport}';
      meetings.putIfAbsent(key, () => []).add(trade);
    }
    final groups = meetings.values.toList();
    final random = Random(20260713);
    final samples = <double>[];
    for (var draw = 0; draw < 2000; draw++) {
      var turnover = 0.0;
      var profit = 0.0;
      for (var index = 0; index < groups.length; index++) {
        for (final trade in groups[random.nextInt(groups.length)]) {
          turnover += trade.stake;
          profit += trade.profit ?? 0;
        }
      }
      samples.add(turnover == 0 ? 0 : profit / turnover);
    }
    samples.sort();
    double percentile(double value) =>
        samples[((samples.length - 1) * value).round()];
    return (
      [percentile(0.05), percentile(0.95)],
      [percentile(0.025), percentile(0.975)],
    );
  }

  Future<BackupImportResult> import(String encoded) async {
    final payload = (jsonDecode(encoded) as Map).cast<String, Object?>();
    if ((payload['schemaVersion'] as num?)?.toInt() != 1 ||
        payload['app'] != 'EdgeWise') {
      throw const FormatException('不是支援的EdgeWise備份。');
    }
    final checksum = payload.remove('checksum') as String?;
    if (checksum == null || checksum != _checksum(jsonEncode(payload))) {
      throw const FormatException('備份checksum不符，檔案可能不完整。');
    }
    final tradeIds = <String>{};
    final trades = (payload['simulatedTrades'] as List<Object?>? ?? const [])
        .map(
          (value) =>
              SimulatedTrade.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList();
    if (trades.any(
      (trade) =>
          trade.id.isEmpty ||
          !trade.stake.isFinite ||
          trade.stake <= 0 ||
          !trade.odds.isFinite ||
          trade.odds <= 1 ||
          trade.odds > 1000 ||
          (trade.marketCapturedAt != null &&
              !trade.marketCapturedAt!.toUtc().isBefore(
                trade.matchDate.toUtc(),
              )) ||
          (trade.minimumAcceptableOdds != null &&
              (!trade.minimumAcceptableOdds!.isFinite ||
                  trade.minimumAcceptableOdds! <= 1)) ||
          !tradeIds.add(trade.id),
    )) {
      throw const FormatException('模擬記錄備份未通過完整性檢查。');
    }
    final snapshotPayload =
        (payload['footballResearchSnapshots'] as Map? ?? const {})
            .cast<String, Object?>();
    final shadows = (payload['shadowForecasts'] as List<Object?>? ?? const [])
        .map(
          (value) =>
              ShadowForecast.fromJson((value as Map).cast<String, Object?>()),
        )
        .toList();
    final shadowIds = <String>{};
    if (shadows.any(
      (record) =>
          record.id.isEmpty ||
          !record.expectedTotalCorners.isFinite ||
          record.expectedTotalCorners < 0 ||
          (record.over9_5Probability != null &&
              (!record.over9_5Probability!.isFinite ||
                  record.over9_5Probability! < 0 ||
                  record.over9_5Probability! > 1)) ||
          !record.capturedAt.toUtc().isBefore(record.matchDate.toUtc()) ||
          ((record.actualTotalCorners == null) != (record.settledAt == null)) ||
          (record.settledAt != null &&
              record.settledAt!.toUtc().isBefore(record.matchDate.toUtc())) ||
          !shadowIds.add(record.id),
    )) {
      throw const FormatException('Shadow預測備份未通過完整性檢查。');
    }
    final footballRecoveryPayload =
        (payload['footballRecovery'] as Map? ?? const {})
            .cast<String, Object?>();
    final racingRecoveryPayload =
        (payload['racingRecovery'] as Map? ?? const {}).cast<String, Object?>();
    final racingSnapshotPayload =
        (payload['racingResearchSnapshots'] as Map? ?? const {})
            .cast<String, Object?>();
    _validateFootballRecovery(footballRecoveryPayload);
    _validateRacingRecovery(racingRecoveryPayload);
    racingStore.validateResearchSnapshots(racingSnapshotPayload);
    final imported = await footballStore.importResearchSnapshots(
      snapshotPayload,
    );
    final racingOddsImported = await racingStore.importResearchSnapshots(
      racingSnapshotPayload,
    );
    final footballRecovery = await footballStore.importRecoveryState(
      footballRecoveryPayload,
    );
    final racingRecovery = await racingStore.importRecoveryState(
      racingRecoveryPayload,
    );
    await simulationService.save(trades);
    await shadowService.save(shadows);
    return BackupImportResult(
      trades: trades,
      oddsImported: imported.$1,
      weatherImported: imported.$2,
      racingOddsImported: racingOddsImported,
      shadowForecasts: shadows.length,
      modelsRestored:
          (footballRecovery.$1 ? 1 : 0) + (racingRecovery.$1 ? 1 : 0),
      checkpointsRestored:
          (footballRecovery.$2 ? 1 : 0) + (racingRecovery.$2 ? 1 : 0),
    );
  }

  static String _checksum(String value) {
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static void _validateFootballRecovery(Map<String, Object?> payload) {
    if ((payload['schemaVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('足球復原資料版本不受支援。');
    }
    final model = payload['activeModel'] as Map?;
    final job = payload['trainingJob'] as Map?;
    if (model != null) {
      MobileFootballModel.fromJson(model.cast<String, Object?>());
    }
    if (job != null) {
      FootballTrainingJob.fromJson(job.cast<String, Object?>());
    }
  }

  static void _validateRacingRecovery(Map<String, Object?> payload) {
    if ((payload['schemaVersion'] as num?)?.toInt() != 1) {
      throw const FormatException('賽馬復原資料版本不受支援。');
    }
    final model = payload['activeModel'] as Map?;
    final job = payload['trainingJob'] as Map?;
    if (model != null) {
      MobileRacingModel.fromJson(model.cast<String, Object?>());
    }
    if (job != null) {
      RacingTrainingJob.fromJson(job.cast<String, Object?>());
    }
  }
}
