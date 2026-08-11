import 'package:flutter/material.dart';

import '../models/forecast_data.dart';
import '../models/shadow_forecast.dart';
import '../models/simulated_trade.dart';
import '../services/football_mobile_service.dart';
import '../services/hkjc_mobile_service.dart';

class ResearchHealthView extends StatelessWidget {
  const ResearchHealthView({
    required this.data,
    required this.footballStatus,
    required this.racingStatus,
    required this.shadowHealth,
    required this.sourceErrors,
    required this.trades,
    required this.onExportReport,
    required this.onExportBackup,
    required this.onImportBackup,
    super.key,
  });

  final ForecastData data;
  final FootballSyncStatus? footballStatus;
  final RacingSyncStatus? racingStatus;
  final ShadowHealth shadowHealth;
  final Map<String, String> sourceErrors;
  final List<SimulatedTrade> trades;
  final Future<void> Function() onExportReport;
  final Future<void> Function() onExportBackup;
  final Future<void> Function() onImportBackup;

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
