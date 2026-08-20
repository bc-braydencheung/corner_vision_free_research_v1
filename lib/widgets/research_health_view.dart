import 'package:flutter/material.dart';

import '../models/feature_ablation.dart';
import '../models/football_mobile.dart';
import '../models/forecast_data.dart';
import '../models/shadow_forecast.dart';
import '../models/simulated_trade.dart';
import '../services/football_mobile_service.dart';
import '../services/hkjc_mobile_service.dart';
import '../services/calibration_service.dart';
import '../services/market_anchor.dart';
import '../services/market_residual.dart';
import '../services/online_learning.dart';
import '../services/provenance.dart';
import '../services/odds_collector_service.dart';
import '../services/model_cards.dart';
import '../services/source_contract.dart';
import '../services/walk_forward.dart';

class ResearchHealthView extends StatelessWidget {
  const ResearchHealthView({
    required this.data,
    required this.footballStatus,
    required this.racingStatus,
    required this.shadowHealth,
    required this.sourceErrors,
    required this.trades,
    this.mirrorHealth = const [],
    this.walkForward = const {},
    this.keptFeatures = const {},
    required this.onExportReport,
    required this.onExportBackup,
    required this.onImportBackup,
    this.footballTrainingJob,
    this.footballSyncing = false,
    this.calibration,
    this.onlineLearning,
    this.marketAnchor,
    this.marketResidual,
    this.provenance,
    this.oddsCollection,
    this.collectingOdds = false,
    this.onCollectOdds,
    this.ablation,
    this.runningAblation = false,
    this.onRunAblation,
    this.onRefreshFootball,
    this.onTrainFootball,
    this.onPauseFootballTraining,
    this.onResumeFootballTraining,
    super.key,
  });

  final ForecastData data;
  final FootballSyncStatus? footballStatus;
  final RacingSyncStatus? racingStatus;
  final ShadowHealth shadowHealth;
  final Map<String, String> sourceErrors;
  final List<SimulatedTrade> trades;

  /// Per-mirror outcome of the last full-model fetch.
  final List<SourceHealth> mirrorHealth;

  /// Purged walk-forward report of every locally trained league.
  final Map<String, WalkForwardReport> walkForward;

  /// Feature names each released league model kept, by league code.
  final Map<String, List<String>> keptFeatures;
  final Future<void> Function() onExportReport;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onImportBackup;
  final FootballTrainingJob? footballTrainingJob;
  final bool footballSyncing;
  final CalibrationState? calibration;
  final OnlineLearningState? onlineLearning;

  /// Hedge-learned market anchor, when it has been measured.
  final MarketAnchorState? marketAnchor;

  /// Learned deviation from the quoted price, when it has been measured.
  final MarketResidualState? marketResidual;
  final ProvenanceLedger? provenance;
  final OddsCollectionReport? oddsCollection;
  final bool collectingOdds;
  final Future<void> Function()? onCollectOdds;

  /// Purged-fold feature attribution, once it has been measured.
  final FeatureAblationReport? ablation;
  final bool runningAblation;
  final Future<void> Function()? onRunAblation;
  final Future<void> Function()? onRefreshFootball;
  final Future<void> Function()? onTrainFootball;
  final Future<void> Function()? onPauseFootballTraining;
  final Future<void> Function()? onResumeFootballTraining;

  @override
  Widget build(BuildContext context) {
    final footballGateCount = data.leagues
        .where((league) => league.model.tradeEnabled)
        .length;
    final driftStops = data.leagues
        .where((league) => league.model.historicalDriftStatus == 'stop')
        .length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text(
          '研究健康中心',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '免費來源、時間戳、模型漂移及復原狀態集中檢查',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
        ),
        const SizedBox(height: 18),
        if (calibration != null) ...[
          _CalibrationCard(state: calibration!),
          const SizedBox(height: 14),
        ] else ...[
          const _SkeletonCard(
            title: '機率校準',
            icon: Icons.tune,
            note: '正在讀取已結算樣本並擬合校準器…',
            rows: 3,
          ),
          const SizedBox(height: 14),
        ],
        if (onlineLearning != null) ...[
          _OnlineLearningCard(state: onlineLearning!),
          const SizedBox(height: 14),
        ] else ...[
          const _SkeletonCard(
            title: '線上學習與漂移',
            icon: Icons.auto_graph,
            note: '正在重放已結算預測更新權重…',
            rows: 2,
          ),
          const SizedBox(height: 14),
        ],
        if (marketAnchor != null) ...[
          _MarketAnchorCard(state: marketAnchor!),
          const SizedBox(height: 14),
        ],
        if (marketResidual != null) ...[
          _MarketResidualCard(state: marketResidual!),
          const SizedBox(height: 14),
        ],
        if (provenance != null && provenance!.entries.isNotEmpty) ...[
          _ProvenanceCard(ledger: provenance!),
          const SizedBox(height: 14),
        ] else if (provenance == null) ...[
          const _SkeletonCard(
            title: '資料來歷',
            icon: Icons.receipt_long,
            note: '正在計算資料集指紋及模型版本…',
            rows: 2,
          ),
          const SizedBox(height: 14),
        ],
        if (mirrorHealth.isNotEmpty) ...[
          _MirrorHealthCard(health: mirrorHealth),
          const SizedBox(height: 14),
        ],
        if (walkForward.isNotEmpty) ...[
          _WalkForwardCard(reports: walkForward),
          const SizedBox(height: 14),
        ],
        if (onRunAblation != null) ...[
          _AblationCard(
            report: ablation,
            kept: keptFeatures,
            running: runningAblation,
            onRun: onRunAblation!,
          ),
          const SizedBox(height: 14),
        ],
        if (onCollectOdds != null) ...[
          _OddsTimelineCard(
            report: oddsCollection,
            collecting: collectingOdds,
            onCollect: onCollectOdds!,
          ),
          const SizedBox(height: 14),
        ],
        if (onRefreshFootball != null) ...[
          _FootballMaintenanceCard(
            status: footballStatus,
            job: footballTrainingJob,
            syncing: footballSyncing,
            onRefresh: onRefreshFootball!,
            onTrain: onTrainFootball,
            onPause: onPauseFootballTraining,
            onResume: onResumeFootballTraining,
          ),
          const SizedBox(height: 14),
        ],
        _HealthCard(
          title: '總體安全狀態',
          icon: Icons.health_and_safety_outlined,
          rows: [
            _HealthRow(
              label: '運作模式',
              value: '統計研究／虛擬模擬',
              state: _HealthState.good,
            ),
            _HealthRow(
              label: '足球市場閘門',
              value: footballGateCount == 0
                  ? '5個聯賽全部停用'
                  : '$footballGateCount個聯賽通過',
              state: footballGateCount == 0
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            _HealthRow(
              label: '歷史漂移停止',
              value: driftStops == 0 ? '沒有' : '$driftStops個聯賽',
              state: driftStops == 0 ? _HealthState.good : _HealthState.bad,
            ),
            _HealthRow(
              label: '前瞻shadow',
              value: _shadowLabel(shadowHealth),
              state: _shadowState(shadowHealth.status),
            ),
            const _HealthRow(
              label: '模型層級',
              value: 'Champion顯示 · Challenger離線驗證 · Shadow交易閘門',
              state: _HealthState.good,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _HealthCard(
          title: '免費資料來源',
          icon: Icons.cloud_outlined,
          rows: [
            _HealthRow(
              label: 'Football-Data',
              value:
                  footballStatus?.latestResults.entries
                      .map((entry) => '${entry.key} ${entry.value}')
                      .join(' · ') ??
                  '等待首次同步',
              state: footballStatus == null
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            _HealthRow(
              label: 'Betfair Basic角球盤',
              value: footballStatus?.marketSnapshotCount == 0
                  ? '0筆；需匯入用戶下載檔'
                  : '${footballStatus!.marketSnapshotCount}筆 · '
                        '${_dateTime(footballStatus!.latestMarketCapturedAt)}',
              state: footballStatus?.marketSnapshotCount == 0
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            _HealthRow(
              label: 'Open-Meteo賽前天氣',
              value: footballStatus?.weatherSnapshotCount == 0
                  ? '0筆；沒有可靠座標便保留缺失'
                  : '${footballStatus!.weatherSnapshotCount}筆 · '
                        '${_dateTime(footballStatus!.latestWeatherCapturedAt)}',
              state: footballStatus?.weatherSnapshotCount == 0
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            _HealthRow(
              label: 'HKJC低頻快取',
              value: racingStatus == null
                  ? '等待首次同步'
                  : '最新完整賽果 ${racingStatus!.latestResultDate}',
              state: racingStatus == null
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            _HealthRow(
              label: '賽馬賠率快照',
              value: (racingStatus?.oddsSnapshotCount ?? 0) == 0
                  ? '0筆；只可用真實賽前快照'
                  : '${racingStatus!.oddsSnapshotCount}筆 · '
                        '${_dateTime(racingStatus!.latestOddsCapturedAt)}',
              state: (racingStatus?.oddsSnapshotCount ?? 0) == 0
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            const _HealthRow(
              label: '傷停／陣容',
              value: '沒有可靠免費歷史源；不推斷為沒有傷停',
              state: _HealthState.warning,
            ),
            for (final error in sourceErrors.entries)
              _HealthRow(
                label: '${error.key}錯誤',
                value: '沿用快取／內置資料 · ${error.value}',
                state: _HealthState.bad,
              ),
          ],
        ),
        const SizedBox(height: 14),
        _HealthCard(
          title: '模型及時間完整性',
          icon: Icons.timeline,
          rows: [
            for (final league in data.leagues)
              _HealthRow(
                label: league.name,
                value:
                    '${league.model.firstSeason}–${league.model.lastSeason} · '
                    '${league.model.trainingMatches}場 · '
                    '${_driftLabel(league.model)}',
                state: _driftState(league.model.historicalDriftStatus),
              ),
            _HealthRow(
              label: '香港賽馬',
              value: data.racing.model.trainingSeasons > 0
                  ? '${data.racing.model.firstSeason}–'
                        '${data.racing.model.lastSeason} · '
                        '${data.racing.model.trainingSeasons}季 · '
                        '${data.racing.model.trainingRaces}場'
                  : '${data.racing.model.trainingRaces}場歷史訓練賽事',
              state: data.racing.model.trainingSeasons >= 5
                  ? _HealthState.good
                  : _HealthState.warning,
            ),
            _HealthRow(
              label: '賽馬獨贏Log Loss',
              value: data.racing.model.trainingRaces == 0
                  ? '尚未有可用模型'
                  : '${data.racing.model.winLogLoss.toStringAsFixed(3)} · '
                        '基準${data.racing.model.baselineWinLogLoss.toStringAsFixed(3)}',
              state: data.racing.model.trainingRaces == 0
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            const _HealthRow(
              label: '時間旅行檢查',
              value: '市場／天氣快照晚於賽事時間會拒絕寫入',
              state: _HealthState.good,
            ),
            const _HealthRow(
              label: '盤口／方向分層',
              value: '等待真實市場快照；缺失時不產生假漂移指標',
              state: _HealthState.warning,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _HealthCard(
          title: '前瞻shadow監察',
          icon: Icons.visibility_outlined,
          rows: [
            _HealthRow(
              label: '已保存／待結算',
              value:
                  '${shadowHealth.totalForecasts}／${shadowHealth.openForecasts}',
              state: shadowHealth.totalForecasts == 0
                  ? _HealthState.warning
                  : _HealthState.good,
            ),
            _HealthRow(
              label: '已結算',
              value: '${shadowHealth.settledForecasts}場',
              state: shadowHealth.settledForecasts >= 30
                  ? _HealthState.good
                  : _HealthState.warning,
            ),
            _HealthRow(
              label: '前瞻MAE',
              value: shadowHealth.settledForecasts == 0
                  ? '等待賽果'
                  : '${shadowHealth.mae.toStringAsFixed(2)} '
                        '（基準 ${shadowHealth.referenceMae.toStringAsFixed(2)}）',
              state: _shadowState(shadowHealth.status),
            ),
            _HealthRow(
              label: '前瞻Brier大9.5',
              value: shadowHealth.settledForecasts == 0
                  ? '等待賽果'
                  : '${shadowHealth.brierOver9_5.toStringAsFixed(3)} '
                        '（基準 ${shadowHealth.referenceBrier.toStringAsFixed(3)}）',
              state: _shadowState(shadowHealth.status),
            ),
          ],
          footer: shadowHealth.message,
        ),
        const SizedBox(height: 14),
        _HealthCard(
          title: '風控及復原',
          icon: Icons.backup_outlined,
          rows: [
            const _HealthRow(
              label: '單項風險',
              value: '最多戶口0.5%',
              state: _HealthState.good,
            ),
            const _HealthRow(
              label: '每日總曝險',
              value: '最多戶口2%',
              state: _HealthState.good,
            ),
            const _HealthRow(
              label: '回撤停機',
              value: '最大回撤達15%停止新增',
              state: _HealthState.good,
            ),
            _HealthRow(
              label: '模擬記錄',
              value: '${trades.length}筆不可修改記錄',
              state: _HealthState.good,
            ),
          ],
          footer:
              '備份包含模擬記錄、角球盤／天氣快照、active模型、checkpoint metadata及shadow預測；checkpoint只有在固定資料快照版本一致時才恢復。',
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onExportReport,
            icon: const Icon(Icons.summarize_outlined),
            label: const Text('一鍵複製研究報告'),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onImportBackup,
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('由剪貼簿復原'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: onExportBackup,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('複製研究備份'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _HealthCard(
          title: '仍需外部資料才能完成',
          icon: Icons.info_outline,
          rows: [
            _HealthRow(
              label: '真實角球市場',
              value: '需用戶以Betfair帳戶免費下載Basic檔',
              state: _HealthState.warning,
            ),
            _HealthRow(
              label: '可信CLV／實際ROI',
              value: '需累積固定時間真實賠率及前瞻結果',
              state: _HealthState.warning,
            ),
          ],
          footer: '系統不會以最終賠率、入球盤或人工1.90冒充角球市場價格。',
        ),
        const SizedBox(height: 14),
        const _ModelCardsCard(),
      ],
    );
  }

  static String _dateTime(DateTime? value) {
    if (value == null) {
      return '沒有時間戳';
    }
    final utc = value.toUtc();
    return '${utc.year}-${utc.month.toString().padLeft(2, '0')}-'
        '${utc.day.toString().padLeft(2, '0')} '
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')} UTC';
  }

  static String _driftLabel(ModelSummary model) {
    return switch (model.historicalDriftStatus) {
      'stable' => '歷史漂移穩定',
      'watch' => '歷史漂移監察',
      'stop' => '歷史漂移停止',
      _ => '漂移樣本不足',
    };
  }

  static String _shadowLabel(ShadowHealth health) {
    return switch (health.status) {
      'stable' => '穩定 · ${health.settledForecasts}場',
      'watch' => '監察 · ${health.settledForecasts}場',
      'stop' => '停止新增 · ${health.settledForecasts}場',
      _ => '累積中 · ${health.settledForecasts}場',
    };
  }

  static _HealthState _driftState(String status) => switch (status) {
    'stable' => _HealthState.good,
    'watch' => _HealthState.warning,
    'stop' => _HealthState.bad,
    _ => _HealthState.warning,
  };

  static _HealthState _shadowState(String status) => switch (status) {
    'stable' => _HealthState.good,
    'watch' => _HealthState.warning,
    'stop' => _HealthState.bad,
    _ => _HealthState.warning,
  };
}

class _ProvenanceCard extends StatelessWidget {
  const _ProvenanceCard({required this.ledger});

  final ProvenanceLedger ledger;

  @override
  Widget build(BuildContext context) {
    final recent = ledger.entries.reversed.take(6).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ledger.intact ? Icons.link : Icons.link_off,
                color: ledger.intact
                    ? const Color(0xFF8BE9A6)
                    : const Color(0xFFFF6B6B),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '資料血緣（provenance）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                ledger.intact ? '雜湊鏈完整' : '雜湊鏈已斷',
                style: TextStyle(
                  color: ledger.intact
                      ? const Color(0xFF8BE9A6)
                      : const Color(0xFFFF6B6B),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            '資料集→特徵→模型→校準→預測→結算每一步都記下免費來源、時間戳與內容雜湊，'
            '並鏈到上一步；任何一步被改動，鏈就會斷，所以顯示的機率可以被追溯查核。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in recent) ...[
            Text(
              '${entry.stage.label} · ${entry.source}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              '${entry.recordedAt.toLocal()} · ${entry.contentHash}'
              '${entry.notes.isEmpty ? '' : ' · ${entry.notes}'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _MirrorHealthCard extends StatelessWidget {
  const _MirrorHealthCard({required this.health});

  final List<SourceHealth> health;

  @override
  Widget build(BuildContext context) {
    final healthy = health.where((entry) => entry.ok).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                healthy > 0 ? Icons.cloud_done_outlined : Icons.cloud_off,
                color: healthy > 0
                    ? const Color(0xFF8BE9A6)
                    : const Color(0xFFFF6B6B),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '免費鏡像健康度',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$healthy/${health.length} 通過',
                style: TextStyle(
                  color: healthy > 0
                      ? const Color(0xFF8BE9A6)
                      : const Color(0xFFFF6B6B),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            '同一份免費模型檔同時向 GitHub Pages、raw.githubusercontent、jsDelivr 及 '
            'githack 取回；每個鏡像都要通過欄位與類型的結構合約，'
            '再取最新的一份，所以單一鏡像部署中斷或返回錯誤內容都不會影響 App。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in health) ...[
            Text(
              Uri.tryParse(entry.url)?.host ?? entry.url,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              entry.label,
              style: TextStyle(
                color: entry.ok
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFFFFC857),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _WalkForwardCard extends StatelessWidget {
  const _WalkForwardCard({required this.reports});

  final Map<String, WalkForwardReport> reports;

  @override
  Widget build(BuildContext context) {
    final passed = reports.values.where((report) => report.gatePassed).length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline_outlined, color: Color(0xFFB491FF)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Purged walk-forward 驗證',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$passed/${reports.length} 通過閘門',
                style: const TextStyle(fontSize: 11, color: Color(0xFFB491FF)),
              ),
            ],
          ),
          Text(
            '按日期擴張訓練窗逐折驗證；每折之間先 purge 特徵重疊期，再加 embargo，'
            '所以測試折不會看到與訓練折共用資訊的比賽。'
            '折數不足 3、或未過半數折勝基準，模型就不會放行。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          for (final entry in reports.entries) ...[
            Text(
              entry.key,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              '${entry.value.passedFolds}/${entry.value.foldCount} 折勝基準 · '
              'MAE ${entry.value.mae.toStringAsFixed(2)}'
              '（基準 ${entry.value.baselineMae.toStringAsFixed(2)}）· '
              'Brier ${entry.value.brier.toStringAsFixed(3)}'
              '（基準 ${entry.value.baselineBrier.toStringAsFixed(3)}）· '
              'purge ${entry.value.purgedRows} / embargo '
              '${entry.value.embargoedRows} 場',
              style: TextStyle(
                color: entry.value.gatePassed
                    ? Colors.white.withValues(alpha: 0.5)
                    : const Color(0xFFFFC857),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _ModelCardsCard extends StatelessWidget {
  const _ModelCardsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.badge_outlined, color: Color(0xFF6FA8FF)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '模型說明卡（model cards）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Text(
            '每個實際運行的模型都列出用途、免費資料來源、方法、放行條件與已知限制。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          for (final card in modelCards)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: Material(
                color: Colors.transparent,
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 10),
                  title: Text(
                    card.name,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    card.purpose,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                  children: [
                    _ModelCardRow(label: '免費資料', value: card.data),
                    _ModelCardRow(label: '方法', value: card.method),
                    _ModelCardRow(label: '放行條件', value: card.gate),
                    _ModelCardRow(label: '已知限制', value: card.limits),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelCardRow extends StatelessWidget {
  const _ModelCardRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6FA8FF),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineLearningCard extends StatelessWidget {
  const _OnlineLearningCard({required this.state});

  final OnlineLearningState state;

  @override
  Widget build(BuildContext context) {
    final drifting = state.drifting;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                drifting ? Icons.warning_amber : Icons.autorenew,
                color: drifting
                    ? const Color(0xFFFFC857)
                    : const Color(0xFF8BE9A6),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '線上學習與漂移監控',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '第 ${state.version} 版',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            '主要學習訊號是收盤價（CLV）：開賽時用馬會最後一口去水後機率評分，'
            '比等賽果早、雜訊亦低；賽果樣本仍然照樣回放。模型與後備（市場開盤價／歷史頻率）'
            '用指數加權（Hedge）競爭，Page–Hinkley 及 CUSUM 監控是否持續變差，'
            '一旦報警即自動回滾到上一個檢查點，資料異常或賽事作廢一律不學習。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '收盤價樣本 ${state.closingLineSamples} · 賽果樣本 ${state.resultSamples}',
            style: const TextStyle(fontSize: 11),
          ),
          Text(
            '學習樣本 ${state.settledSamples} · 模型權重 '
            '${(state.modelWeight * 100).round()}% · 組合 Brier '
            '${state.blendBrier.toStringAsFixed(3)}'
            '（最佳單一 ${state.championBrier.toStringAsFixed(3)}）',
            style: const TextStyle(fontSize: 11),
          ),
          Text(
            'Page–Hinkley ${state.pageHinkley.statistic.toStringAsFixed(3)}'
            ' · CUSUM ${state.cusum.positive.toStringAsFixed(3)}'
            ' · 回滾 ${state.rollbacks} 次'
            ' · 檢查點 ${state.checkpoints.length} 個',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${state.event.label}：${state.note}',
            style: TextStyle(
              color: drifting
                  ? const Color(0xFFFFC857)
                  : const Color(0xFF8BE9A6),
              fontSize: 11,
            ),
          ),
          if (state.skipped.isNotEmpty)
            Text(
              '已拒絕樣本：'
              '${state.skipped.entries.map((entry) => '${entry.key} ${entry.value}').join(' · ')}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _MarketAnchorCard extends StatelessWidget {
  const _MarketAnchorCard({required this.state});

  final MarketAnchorState state;

  @override
  Widget build(BuildContext context) {
    final learned = state.learned;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                learned ? Icons.balance : Icons.hourglass_bottom,
                color: learned
                    ? const Color(0xFF8BE9A6)
                    : const Color(0xFFFFC857),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '市場錨定權重（Hedge 學得）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                learned ? '已學得' : '保守預設',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            '模型與馬會公平機率的分歧保留幾多，不再寫死：'
            '${marketAnchorCandidates.map((value) => value.toStringAsFixed(2)).join('、')} '
            '四個候選權重在已結算樣本上以 Brier 損失互相競爭，'
            'Page–Hinkley 報警即忘記所學回到均勻權重，'
            '樣本不足或漂移時一律用保守值。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '保留模型觀點 ${(state.share * 100).round()}% · '
            '帶市場價已結算樣本 ${state.samples} 筆 · '
            '錨定後 Brier ${state.brier.toStringAsFixed(3)}'
            '（純市場價 ${state.marketBrier.toStringAsFixed(3)}）',
            style: const TextStyle(fontSize: 11),
          ),
          Text(
            state.samples == 0
                ? '尚未有帶市場價的已結算樣本。'
                : state.beatsMarket
                ? '目前錨定後機率的 Brier 優於純市場價。'
                : '目前錨定後機率未優於純市場價，權重會繼續向市場收斂。',
            style: TextStyle(
              color: state.beatsMarket
                  ? const Color(0xFF8BE9A6)
                  : const Color(0xFFFFC857),
              fontSize: 11,
            ),
          ),
          if (state.note.isNotEmpty)
            Text(
              state.note,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

/// Learned deviation from the quoted price, kept honest about its holdout.
class _MarketResidualCard extends StatelessWidget {
  const _MarketResidualCard({required this.state});

  final MarketResidualState state;

  @override
  Widget build(BuildContext context) {
    final adopted = state.adopted;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                adopted ? Icons.compare_arrows : Icons.hourglass_bottom,
                color: adopted
                    ? const Color(0xFF8BE9A6)
                    : const Color(0xFFFFC857),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '市場偏離模型（residual）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                adopted ? '已啟用' : '未啟用',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          Text(
            '不再只獨立預測角球數再同盤口比：'
            '以馬會去水後的公平機率做基底，'
            '直接學「模型與盤口的分歧幾時真的對」。'
            '只用捕取時的盤口（不用收盤價），'
            '而且只有在時間切分的 holdout 上 Brier 與 log loss 同時勝過盤口才會啟用。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '帶市場價已結算樣本 ${state.samples} 筆 · '
            'holdout ${state.holdout} 筆 · '
            '常數 ${state.bias.toStringAsFixed(3)} · '
            '分歧保留 ${state.gapWeight.toStringAsFixed(3)}',
            style: const TextStyle(fontSize: 11),
          ),
          if (state.holdout > 0)
            Text(
              'holdout Brier ${state.brier.toStringAsFixed(4)}'
              '（盤口 ${state.marketBrier.toStringAsFixed(4)}）· '
              'log loss ${state.logLoss.toStringAsFixed(4)}'
              '（盤口 ${state.marketLogLoss.toStringAsFixed(4)}）',
              style: TextStyle(
                color: state.beatsMarket
                    ? const Color(0xFF8BE9A6)
                    : const Color(0xFFFFC857),
                fontSize: 11,
              ),
            ),
          if (state.note.isNotEmpty)
            Text(
              state.note,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

class _CalibrationCard extends StatelessWidget {
  const _CalibrationCard({required this.state});

  final CalibrationState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.tune, color: Color(0xFF4FC3F7)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '機率校準審核',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          Text(
            '每個市場分開用已結算樣本重新校準，再以 Brier 技巧分數及 ECE 檢查機率是否對應真實頻率；'
            '樣本不足時只顯示原始分數，不會當成已校準機率。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          for (final market in state.markets) ...[
            Text(
              market.market,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              market.report.verdict,
              style: TextStyle(
                color: market.report.beatsBaseline
                    ? const Color(0xFF8BE9A6)
                    : const Color(0xFFFFC857),
                fontSize: 11,
              ),
            ),
            Text(
              '${market.calibrator.label} · Brier '
              '${market.report.brier.toStringAsFixed(3)}'
              '（基準 ${market.report.baselineBrier.toStringAsFixed(3)}）',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _OddsTimelineCard extends StatelessWidget {
  const _OddsTimelineCard({
    required this.report,
    required this.collecting,
    required this.onCollect,
  });

  /// Minimum number of stored quotes before a closing line is worth grading.
  static const _minimumSample = 30;

  final OddsCollectionReport? report;
  final bool collecting;
  final Future<void> Function() onCollect;

  @override
  Widget build(BuildContext context) {
    final current = report;
    final football = current?.footballStored ?? 0;
    final racing = current?.racingStored ?? 0;
    final total = football + racing;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timeline, color: Color(0xFFFFC857)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '馬會賠率走勢收集',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '立即收集一次',
                onPressed: collecting ? null : onCollect,
                icon: const Icon(Icons.download_for_offline_outlined),
              ),
            ],
          ),
          Text(
            '每次抓取都附上收集時間並且永不覆寫，累積後可還原開盤價、收盤價與走勢；收盤價在賽果之前就到手，是免費而最快的學習訊號。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            collecting ? '正在收集馬會賠率…' : '足球角球盤 $football 筆 · 賽馬獨贏 $racing 筆',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (current != null) ...[
            const SizedBox(height: 4),
            Text(
              '本次新增：足球 ${current.footballCaptured} · 賽馬 ${current.racingCaptured}'
              '${current.latestFootballCapture != null ? ' · 最後收集 ${_stamp(current.latestFootballCapture!)}' : ''}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            if (current.note.isNotEmpty)
              Text(
                current.note,
                style: const TextStyle(color: Color(0xFFFFC857), fontSize: 11),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            total < _minimumSample
                ? '樣本不足（少於 $_minimumSample 筆）：暫時不會用走勢做校準或收盤價評分。'
                : '樣本足夠：已可計算開盤／收盤價與收盤價差（CLV）。',
            style: TextStyle(
              color: total < _minimumSample
                  ? const Color(0xFFFFC857)
                  : const Color(0xFF8BE9A6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime time) {
    final local = time.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month-$day $hour:$minute';
  }
}

class _AblationCard extends StatelessWidget {
  const _AblationCard({
    required this.report,
    required this.kept,
    required this.running,
    required this.onRun,
  });

  /// How many features to name per league; the full table is the stored report.
  static const _shown = 3;

  final FeatureAblationReport? report;

  /// Features the released model of each league is allowed to read.
  final Map<String, List<String>> kept;
  final bool running;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    final current = report;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rule_folder_outlined, color: Color(0xFF4FC3F7)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '特徵歸因（purged 折內 ablation）',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '重新計算',
                onPressed: running ? null : onRun,
                icon: const Icon(Icons.play_circle_outline),
              ),
            ],
          ),
          Text(
            '逐個特徵在 purged walk-forward 折內移除，再看折外 MAE 與 Brier 差幾多；'
            '變差越多代表該特徵真有訊號，變好則代表它只是噪音。'
            '訓練只保留排名最高、最多 5 個特徵，而且精簡特徵集要在折外不差於全特徵才採用。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          if (running)
            const Text(
              '正在逐個特徵重跑折內驗證…（22 個特徵，需時較長）',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            )
          else if (current == null || current.isEmpty)
            Text(
              current == null
                  ? '尚未計算：按右上角開始，計算在背景 isolate 進行。'
                  : '樣本不足，未能在折內量度任何特徵。${current.note}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            )
          else ...[
            for (final league in current.leagues) ...[
              Text(
                '${league.name} · ${league.folds} 折 · ${league.samples} 場 · '
                '折外 MAE ${league.baseMae.toStringAsFixed(3)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                league.useful.isEmpty
                    ? '沒有特徵在折外顯示可測訊號'
                    : '有訊號：${_summary(league.useful)}',
                style: TextStyle(
                  color: league.useful.isEmpty
                      ? const Color(0xFFFFC857)
                      : const Color(0xFF8BE9A6),
                  fontSize: 11,
                ),
              ),
              if (league.harmful.isNotEmpty)
                Text(
                  '移除反而更好：${_summary(league.harmful)}',
                  style: const TextStyle(
                    color: Color(0xFFFFC857),
                    fontSize: 11,
                  ),
                ),
              Text(
                kept[league.code] == null
                    ? '當前模型：仍讀全部特徵（篩選未採用或尚未重訓）'
                    : '當前模型只讀：${kept[league.code]!.join('、')}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              '量度於資料版本 ${current.datasetVersion}'
              '${current.note.isEmpty ? '' : ' · ${current.note}'}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 10.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _summary(List<FeatureAblationEntry> entries) => entries
      .take(_shown)
      .map(
        (entry) =>
            '${entry.name} '
            '${entry.maeDelta >= 0 ? '+' : ''}'
            '${entry.maeDelta.toStringAsFixed(3)}',
      )
      .join(' · ');
}

class _FootballMaintenanceCard extends StatelessWidget {
  const _FootballMaintenanceCard({
    required this.status,
    required this.job,
    required this.syncing,
    required this.onRefresh,
    required this.onTrain,
    required this.onPause,
    required this.onResume,
  });

  final FootballSyncStatus? status;
  final FootballTrainingJob? job;
  final bool syncing;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onTrain;
  final Future<void> Function()? onPause;
  final Future<void> Function()? onResume;

  @override
  Widget build(BuildContext context) {
    final running = job?.status == 'queued' || job?.status == 'training';
    final paused = job?.isPaused ?? false;
    final canTrain =
        status?.hasNewResults == true ||
        job?.status == 'failed' ||
        running ||
        paused;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_sync, color: Color(0xFF4FC3F7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncing ? '正在檢查歷史賽果資料…' : status?.message ?? '足球歷史資料快取已載入',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '檢查歷史資料更新',
                onPressed: syncing ? null : onRefresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            '歷史賽果只作模型訓練及研究健康檢查；賽程與盤口以馬會為唯一顯示來源。',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 11,
            ),
          ),
          if (job != null) ...[
            const SizedBox(height: 12),
            if (running)
              LinearProgressIndicator(
                value: (job!.progress / 100).clamp(0.0, 1.0),
              ),
            const SizedBox(height: 7),
            Text(
              '${job!.stage} · ${job!.progress.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12),
            ),
            if (job!.error != null && job!.error!.isNotEmpty)
              Text(
                job!.error!,
                style: const TextStyle(color: Color(0xFFFFC857), fontSize: 11),
              ),
          ],
          if (running && onPause != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPause,
                icon: const Icon(Icons.pause),
                label: const Text('暫停訓練'),
              ),
            ),
          ],
          if (paused && onResume != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('繼續'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onTrain,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新開始'),
                  ),
                ),
              ],
            ),
          ],
          if (canTrain && !running && !paused && onTrain != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onTrain,
                icon: const Icon(Icons.model_training),
                label: Text(job?.status == 'failed' ? '繼續上次訓練' : '重新訓練統計模型'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Placeholder shown while an audit card is still being computed.
///
/// The audit layers read every settled sample before they can say anything, so
/// the page reserves their space and says it is working instead of looking as
/// if the cards are missing.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({
    required this.title,
    required this.icon,
    required this.note,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final String note;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.35)),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(width: 10),
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < rows; index++) ...[
            Container(
              height: 11,
              width: index.isEven ? double.infinity : 190,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            note,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.title,
    required this.icon,
    required this.rows,
    this.footer,
  });

  final String title;
  final IconData icon;
  final List<_HealthRow> rows;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF10291F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF42E695)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          for (final row in rows) row,
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({
    required this.label,
    required this.value,
    required this.state,
  });

  final String label;
  final String value;
  final _HealthState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _HealthState.good => const Color(0xFF42E695),
      _HealthState.warning => const Color(0xFFFFC857),
      _HealthState.bad => const Color(0xFFFF8FA3),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

enum _HealthState { good, warning, bad }
