import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../marksix_lab/lab_view.dart';
import '../models/marksix_mobile.dart';
import '../services/marksix_service.dart';

/// Mark Six research surface: statistical mode plus the disruptive lab.
///
/// The main dashboard no longer links here; the feature is kept whole so it can
/// be reattached to a navigation entry without rebuilding it.
class MarkSixPage extends StatefulWidget {
  const MarkSixPage({super.key});

  @override
  State<MarkSixPage> createState() => _MarkSixPageState();
}

class _MarkSixPageState extends State<MarkSixPage> {
  final MarkSixService _service = MarkSixService();
  List<MarkSixDraw> _draws = [];
  MarkSixStats? _stats;
  MarkSixPrediction? _prediction;
  List<MarkSixCorrection> _corrections = [];
  bool _loading = false;
  String _viewMode = 'stats';
  String _engineMode = 'stats';
  int _backtestDone = 0;
  int _backtestTotal = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _init() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await _service.initialize();
      var draws = await _service.store.loadDraws();
      if (draws.isEmpty) {
        final count = await _service.syncFromRemote();
        if (count > 0) {
          draws = await _service.store.loadDraws();
        }
      }
      final stats = await _service.computeAndSaveStats();
      final prediction = await _service.loadCachedPrediction();
      if (!mounted) return;
      setState(() {
        _draws = draws;
        _stats = stats;
        _prediction = prediction;
      });
    } on Object {
      // An empty state is the honest fallback when the mirror is unreachable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshStats() async {
    final stats = await _service.computeAndSaveStats();
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  Future<void> _generatePrediction() async {
    setState(() => _loading = true);
    try {
      final prediction = await _service.generatePrediction();
      if (!mounted) return;
      setState(() {
        _prediction = prediction;
        _viewMode = 'prediction';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runBacktest() async {
    setState(() => _loading = true);
    try {
      _backtestDone = 0;
      _backtestTotal = 0;
      final corrections = await _service.runBacktest(
        minTraining: 50,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _backtestDone = done;
              _backtestTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _corrections = corrections;
        _viewMode = 'prediction';
      });
      if (corrections.isNotEmpty) {
        final avgMatches =
            corrections.map((c) => c.matches).reduce((a, b) => a + b) /
            corrections.length;
        _showMessage('回測完成：${corrections.length}期，平均命中$avgMatches個號碼');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncFromApi() async {
    setState(() => _loading = true);
    try {
      final count = await _service.syncFromRemote();
      if (!mounted) return;
      if (count == 0) {
        _showMessage('沒有新賽果，已是最新。');
        return;
      }
      final allDraws = await _service.store.loadDraws();
      final stats = await _service.computeAndSaveStats();
      setState(() {
        _draws = allDraws;
        _stats = stats;
      });
      _showMessage('已下載 $count 期新賽果！共 ${allDraws.length} 期');
    } on Object catch (error) {
      if (mounted) _showMessage('同步失敗：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 'stats',
                icon: Icon(Icons.insights),
                label: Text('統計模式'),
              ),
              ButtonSegment(
                value: 'lab',
                icon: Icon(Icons.science),
                label: Text('顛覆模式'),
              ),
            ],
            selected: {_engineMode},
            onSelectionChanged: (selection) {
              setState(() => _engineMode = selection.first);
            },
          ),
        ),
        Expanded(
          child: _engineMode == 'lab'
              ? const MarkSixLabView()
              : _MarkSixStatsView(
                  draws: _draws,
                  stats: _stats,
                  prediction: _prediction,
                  corrections: _corrections,
                  loading: _loading,
                  viewMode: _viewMode,
                  onRefreshStats: _refreshStats,
                  onGeneratePrediction: _generatePrediction,
                  onRunBacktest: _runBacktest,
                  onViewModeChanged: (mode) {
                    setState(() => _viewMode = mode);
                  },
                  onSyncFromApi: _syncFromApi,
                  backtestDone: _backtestDone,
                  backtestTotal: _backtestTotal,
                ),
        ),
      ],
    );
  }
}

// ---- 六合彩統計模式（目前無入口，保留供日後重新掛回）----

class _MarkSixStatsView extends StatelessWidget {
  const _MarkSixStatsView({
    required this.draws,
    required this.stats,
    required this.prediction,
    required this.corrections,
    required this.loading,
    required this.viewMode,
    required this.onRefreshStats,
    required this.onGeneratePrediction,
    required this.onRunBacktest,
    required this.onViewModeChanged,
    required this.onSyncFromApi,
    this.backtestDone = 0,
    this.backtestTotal = 0,
  });

  final List<MarkSixDraw> draws;
  final MarkSixStats? stats;
  final MarkSixPrediction? prediction;
  final List<MarkSixCorrection> corrections;
  final bool loading;
  final String viewMode;
  final VoidCallback onRefreshStats;
  final VoidCallback onGeneratePrediction;
  final VoidCallback onRunBacktest;
  final ValueChanged<String> onViewModeChanged;
  final VoidCallback onSyncFromApi;
  final int backtestDone;
  final int backtestTotal;

  @override
  Widget build(BuildContext context) {
    if (loading && draws.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async => onRefreshStats(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          // Cloud sync banner
          if (draws.isEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC857).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_download,
                        size: 18,
                        color: Color(0xFFFFC857),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loading ? '正在從雲端下載數據...' : '尚未載入六合彩數據',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '點擊下方按鈕從 GitHub Pages 鏡像下載\n1993年至今全部六合彩賽果',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  if (loading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFFFFC857),
                      ),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: onSyncFromApi,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('從雲端下載全部數據'),
                    ),
                  ],
                ],
              ),
            )
          else
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF42E695).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF42E695).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_done,
                    size: 16,
                    color: Color(0xFF42E695),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已載入 ${draws.length} 期數據',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: loading ? null : onSyncFromApi as VoidCallback?,
                    icon: loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 14),
                    label: Text(
                      loading ? '同步中' : '檢查更新',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Row(
            children: [
              _ActionChip(
                icon: Icons.refresh,
                label: '統計',
                selected: viewMode == 'stats',
                onTap: () => onViewModeChanged('stats'),
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Icons.list_alt,
                label: '賽果',
                selected: viewMode == 'results',
                onTap: () => onViewModeChanged('results'),
              ),
              const SizedBox(width: 6),
              _ActionChip(
                icon: Icons.psychology,
                label: '預測',
                selected: viewMode == 'prediction',
                onTap: () => onViewModeChanged('prediction'),
              ),
              const Spacer(),
              Text(
                '${draws.length}期',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Content by mode
          if (stats != null && viewMode == 'stats') ...[
            _StatsDashboard(stats: stats!),
          ] else if (viewMode == 'results') ...[
            if (draws.isEmpty)
              const _EmptyState(message: '尚未載入六合彩數據\n請用 Python 爬蟲下載歷史賽果'),
            for (final draw in draws.reversed.take(20)) _DrawCard(draw: draw),
            if (draws.length > 20)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '顯示最近20期（共${draws.length}期）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ),
          ] else if (viewMode == 'prediction') ...[
            _PredictionPanel(
              prediction: prediction,
              corrections: corrections,
              onGenerate: onGeneratePrediction,
              onBacktest: onRunBacktest,
              backtestDone: backtestDone,
              backtestTotal: backtestTotal,
            ),
          ],

          const SizedBox(height: 20),
          _Disclaimer(text: '六合彩為完全隨機遊戲，所有統計及預測僅供個人研究參考，不構成投注建議。'),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF42E695).withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF42E695).withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? const Color(0xFF42E695) : Colors.white54,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? const Color(0xFF42E695) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Stats Dashboard ----

class _StatsDashboard extends StatelessWidget {
  const _StatsDashboard({required this.stats});
  final MarkSixStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📊 統計概覽',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        // Key metrics row
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatCard(
              label: '總期數',
              value: '${stats.totalDraws}',
              color: const Color(0xFF42E695),
            ),
            _StatCard(
              label: '奇偶比',
              value: stats.oddEvenRatio.toStringAsFixed(2),
              color: const Color(0xFF7FD1FF),
            ),
            _StatCard(
              label: '平均總和',
              value: stats.avgSum.toStringAsFixed(0),
              color: const Color(0xFFB491FF),
            ),
            _StatCard(
              label: '連號率',
              value: '${(stats.consecutiveRate * 100).toStringAsFixed(0)}%',
              color: const Color(0xFFFFC857),
            ),
            _StatCard(
              label: '平均頭獎',
              value: '\$${(stats.topPrizeAvg / 10000).toStringAsFixed(0)}萬',
              color: const Color(0xFFFF8FA3),
            ),
            _StatCard(
              label: '平均投注額',
              value: '\$${(stats.avgTurnover / 1000000).toStringAsFixed(0)}M',
              color: const Color(0xFF42E695),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // Hot numbers
        const Text(
          '🔥 近期熱號',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _NumberBalls(numbers: stats.hotNumbers, color: const Color(0xFFFF8FA3)),
        const SizedBox(height: 16),
        // Cold numbers
        const Text(
          '❄️ 近期冷號',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _NumberBalls(
          numbers: stats.coldNumbers,
          color: const Color(0xFF7FD1FF),
        ),
        const SizedBox(height: 20),
        // Frequency grid
        const Text(
          '📈 號碼頻率分佈',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _FrequencyGrid(frequency: stats.numberFrequency),
        const SizedBox(height: 12),
        Text(
          '日期範圍：${stats.dateRange}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberBalls extends StatelessWidget {
  const _NumberBalls({required this.numbers, required this.color});
  final List<int> numbers;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final n in numbers)
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.5),
                  color.withValues(alpha: 0.25),
                ],
              ),
              border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
      ],
    );
  }
}

class _FrequencyGrid extends StatelessWidget {
  const _FrequencyGrid({required this.frequency});
  final Map<String, int> frequency;

  @override
  Widget build(BuildContext context) {
    final maxFreq = frequency.values.isEmpty ? 1 : frequency.values.reduce(max);
    final entries = frequency.entries.toList()
      ..sort((a, b) => int.parse(a.key).compareTo(int.parse(b.key)));

    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (final entry in entries)
          Container(
            width: 27,
            height: 34,
            decoration: BoxDecoration(
              color: _heatColor(entry.value, maxFreq).withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _heatColor(int value, int max) {
    final ratio = max > 0 ? value / max : 0.0;
    if (ratio > 0.8) return const Color(0xFFFF8FA3);
    if (ratio > 0.6) return const Color(0xFFFFC857);
    if (ratio > 0.35) return const Color(0xFF42E695);
    return const Color(0xFF7FD1FF);
  }
}

// ---- Draw Card ----

class _DrawCard extends StatelessWidget {
  const _DrawCard({required this.draw});
  final MarkSixDraw draw;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0D241A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(label: draw.drawNumber, color: const Color(0xFFB491FF)),
              const SizedBox(width: 8),
              Text(
                draw.drawDate,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              if (draw.totalTurnover > 0)
                _Pill(
                  label:
                      '總投注: \$${(draw.totalTurnover / 1000000).toStringAsFixed(1)}M',
                  color: const Color(0xFF42E695),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              ...draw.numbers.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFF8FA3), Color(0x66FF8FA3)],
                      ),
                      border: Border.all(
                        color: const Color(0xFFFF8FA3).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$n',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF42E695), Color(0x6642E695)],
                  ),
                  border: Border.all(
                    color: const Color(0xFF42E695).withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '特',
                      style: TextStyle(fontSize: 8, color: Colors.white54),
                    ),
                    Text(
                      '${draw.specialNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (draw.prizes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(color: Colors.white.withValues(alpha: 0.06)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in draw.prizes.take(4))
                  Text(
                    '${p.name}: \$${_fmt(p.prizePerUnit)} (${_units(p.winningUnits)}注)',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  String _units(double u) => (u / 10) == (u / 10).roundToDouble()
      ? (u / 10).toStringAsFixed(0)
      : (u / 10).toStringAsFixed(1);
}

class _PredictionPanel extends StatelessWidget {
  const _PredictionPanel({
    required this.prediction,
    required this.corrections,
    required this.onGenerate,
    required this.onBacktest,
    this.backtestDone = 0,
    this.backtestTotal = 0,
  });
  final MarkSixPrediction? prediction;
  final List<MarkSixCorrection> corrections;
  final VoidCallback onGenerate;
  final VoidCallback onBacktest;
  final int backtestDone;
  final int backtestTotal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎯 AI 預測',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('產生預測'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onBacktest,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('回測評估'),
              ),
            ),
          ],
        ),

        // Backtest progress indicator
        if (backtestTotal > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
              Text(
                '回測中 $backtestDone/$backtestTotal',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: backtestDone / backtestTotal,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
          ),
        ],

        const SizedBox(height: 16),
        if (prediction != null &&
            prediction!.recommendedNumbers.isNotEmpty) ...[
          Center(
            child: _Pill(
              label:
                  '信心: ${prediction!.confidenceLabel == 'high'
                      ? '高'
                      : prediction!.confidenceLabel == 'medium'
                      ? '中'
                      : '低'} (${prediction!.confidence.toStringAsFixed(0)}%)',
              color: prediction!.confidenceLabel == 'high'
                  ? const Color(0xFF42E695)
                  : prediction!.confidenceLabel == 'medium'
                  ? const Color(0xFFFFC857)
                  : const Color(0xFFFF8FA3),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '推介號碼',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 8,
            children: [
              ...prediction!.recommendedNumbers.map(
                (n) => Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFF8FA3), Color(0x66FF8FA3)],
                    ),
                    border: Border.all(
                      color: const Color(0xFFFF8FA3).withValues(alpha: 0.7),
                      width: 2.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFF42E695), Color(0x6642E695)],
                  ),
                  border: Border.all(
                    color: const Color(0xFF42E695).withValues(alpha: 0.7),
                    width: 2.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '特',
                      style: TextStyle(fontSize: 9, color: Colors.white70),
                    ),
                    Text(
                      '${prediction!.specialNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Per-number reasoning
          if (prediction!.numberReasoning.isNotEmpty) ...[
            const Text(
              '推介邏輯',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final entry in prediction!.numberReasoning.entries)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [Color(0xFFFF8FA3), Color(0x66FF8FA3)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${entry.key}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.value['主因'] as String? ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF42E695),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '頻率${entry.value['頻率貢獻'] ?? '-'} · 馬可夫${entry.value['馬可夫貢獻'] ?? '-'}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${((double.tryParse((entry.value['機率'] as String?) ?? '0') ?? 0) * 100).toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // Pattern-based prediction (parallel)
          if (prediction!.patternNumbers.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFB491FF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFB491FF).withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.grid_view,
                        size: 16,
                        color: Color(0xFFB491FF),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '結構模式預測',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB491FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    prediction!.patternReasoning['reason'] as String? ?? '',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 6,
                    children: [
                      ...prediction!.patternNumbers.map(
                        (n) => Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFB491FF), Color(0x66B491FF)],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFFB491FF,
                              ).withValues(alpha: 0.7),
                              width: 2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$n',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFF42E695), Color(0x6642E695)],
                          ),
                          border: Border.all(
                            color: const Color(
                              0xFF42E695,
                            ).withValues(alpha: 0.7),
                            width: 2,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${prediction!.patternSpecial}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          ...prediction!.factors.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $f',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ] else if (prediction?.confidenceLabel == 'insufficient') ...[
          const _EmptyState(message: '數據不足，需至少50期歷史數據'),
        ],
        if (corrections.isNotEmpty) ...[
          const SizedBox(height: 24),

          // Best prediction ever
          _buildBestMatch(corrections),

          const SizedBox(height: 16),
          const Text(
            '📋 修正記錄',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final c in corrections.reversed.take(5))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${c.drawDate}: 命中${c.matches}/6 (累積: ${(c.rollingAccuracy * 100).toStringAsFixed(0)}%)',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC857).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber,
                size: 16,
                color: Color(0xFFFFC857),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '六合彩為完全隨機遊戲。AI預測僅供統計研究，不構成投注建議。',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildBestMatch(List<MarkSixCorrection> corrections) {
    if (corrections.isEmpty) return const SizedBox.shrink();
    final best = corrections.reduce((a, b) => a.matches > b.matches ? a : b);
    if (best.matches == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF42E695).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF42E695).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.emoji_events,
                size: 16,
                color: Color(0xFFFFC857),
              ),
              const SizedBox(width: 6),
              Text(
                '最高命中 · ${best.drawDate} · ${best.matches}/6',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFFC857),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '預測',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ...best.predictedNumbers.map(
                (n) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF8FA3).withValues(alpha: 0.3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFFF8FA3),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '實際',
            style: TextStyle(fontSize: 10, color: Colors.white38),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ...best.actualNumbers.map(
                (n) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF42E695).withValues(alpha: 0.3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF42E695),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline,
          size: 16,
          color: Colors.white.withValues(alpha: 0.42),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              height: 1.45,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
