import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../lab_state.dart';
import '../core/combinatorics.dart';
import '../data/draw.dart';
import '../data/history_csv.dart';
import '../stats/bias_audit.dart';
import '../stats/mixing_tests.dart';
import '../stats/power.dart';
import '../stats/rmt.dart';
import 'theme.dart';
import 'widgets/charts.dart';
import 'widgets/panels.dart';

/// The three Monte Carlo passes are far too heavy for the UI isolate (order
/// 10^6 seeded subset draws), so they run through [compute].
class _AuditResult {
  const _AuditResult(this.bias, this.rmt, this.mixing);

  final BiasAuditReport bias;
  final RmtReport rmt;
  final MixingReport mixing;
}

_AuditResult _runAudit(List<Draw> history) => _AuditResult(
  BiasAudit.run(history, monteCarloSamples: 600),
  RmtAnalysis.run(history, monteCarloSamples: 200),
  MixingTests.run(history, monteCarloSamples: 300),
);

class AuditPage extends StatefulWidget {
  const AuditPage({super.key, required this.state});

  final LabState state;

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  BiasAuditReport? _bias;
  RmtReport? _rmt;
  MixingReport? _mixing;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    final result = await compute(_runAudit, widget.state.history.toList());
    if (!mounted) return;
    setState(() {
      _bias = result.bias;
      _rmt = result.rmt;
      _mixing = result.mixing;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(text: '資料集'),
              Tab(text: '球號頻率'),
              Tab(text: '能階間距（RMT）'),
              Tab(text: '混合結構'),
              Tab(text: '統計檢定力'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _DatasetTab(
                  state: widget.state,
                  running: _running,
                  onRun: _run,
                ),
                _FrequencyTab(report: _bias, running: _running, onRun: _run),
                _RmtTab(report: _rmt, running: _running, onRun: _run),
                _MixingTab(report: _mixing, running: _running, onRun: _run),
                _PowerTab(availableDraws: widget.state.history.length),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RunBar extends StatelessWidget {
  const _RunBar({required this.running, required this.onRun});

  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        FilledButton.icon(
          onPressed: running ? null : onRun,
          icon: running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(running ? '正在跑蒙地卡羅…' : '執行審計'),
        ),
      ],
    );
  }
}

class _DatasetTab extends StatefulWidget {
  const _DatasetTab({
    required this.state,
    required this.running,
    required this.onRun,
  });

  final LabState state;
  final bool running;
  final VoidCallback onRun;

  @override
  State<_DatasetTab> createState() => _DatasetTabState();
}

class _DatasetTabState extends State<_DatasetTab> {
  final TextEditingController _csv = TextEditingController();
  String? _importMessage;

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  void _import() {
    final result = HistoryCsv.parse(_csv.text);
    if (result.draws.isEmpty) {
      setState(
        () => _importMessage = '找不到有效資料列。${result.errors.take(3).join('；')}',
      );
      return;
    }
    widget.state.setImportedHistory(
      result.draws,
      '已匯入 ${result.draws.length} 期'
      '${result.errors.isEmpty ? '' : '，略過 ${result.errors.length} 列'}。',
    );
    setState(
      () => _importMessage =
          '已匯入 ${result.draws.length} 期，略過 ${result.errors.length} 列。',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        InfoBanner(
          icon: Icons.dataset_outlined,
          color: state.historySource == HistorySource.synthetic
              ? kAccentWarm
              : kAccent,
          text: state.historyNote,
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '對照實驗',
          subtitle:
              '內建資料集刻意用合成數據。你可以在某一顆球上注入已知偏差，'
              '再跑審計，看看以一生能累積的期數究竟能否偵測到。',
          child: Column(
            children: <Widget>[
              LabeledSlider(
                label: '期數',
                value: state.syntheticDraws.toDouble(),
                min: 200,
                max: 6000,
                divisions: 29,
                display: state.syntheticDraws.toString(),
                onChanged: (v) =>
                    state.configureSynthetic(draws: (v / 200).round() * 200),
              ),
              LabeledSlider(
                label: '偏差球號',
                value: (state.injectedBiasBall ?? 1).toDouble(),
                min: 1,
                max: kBallCount.toDouble(),
                divisions: kBallCount - 1,
                display: state.injectedBiasBall?.toString() ?? '無',
                onChanged: (v) =>
                    state.configureSynthetic(biasedBall: v.round()),
              ),
              LabeledSlider(
                label: '注入的相對偏差',
                value: state.injectedBias,
                min: 0,
                max: 0.5,
                display: '${(state.injectedBias * 100).toStringAsFixed(1)}%',
                onChanged: (v) => state.configureSynthetic(relativeBias: v),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => state.configureSynthetic(clearBias: true),
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('公平機器'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => state.regenerateSynthetic(newSeed: true),
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('重新抽樣'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '匯入真實賽果',
          subtitle:
              '按 期數,日期,n1..n6[,特別號][,頭獎中獎注數] 貼上官方紀錄。'
              '有中獎注數才能校準人群模型。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _csv,
                maxLines: 6,
                style: kMonoStyle.copyWith(fontSize: 12),
                decoration: const InputDecoration(
                  hintText: '24/001,2024-01-02,4,11,23,28,39,44,7,1.5',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('匯入'),
                  ),
                  const SizedBox(width: 12),
                  if (_importMessage != null)
                    Expanded(
                      child: Text(
                        _importMessage!,
                        style: const TextStyle(fontSize: 12, color: kMuted),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '執行',
          subtitle: '三個檢定都用「不放回抽樣」的精確蒙地卡羅虛無分佈，而不是漸近近似。',
          child: _RunBar(running: widget.running, onRun: widget.onRun),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _FrequencyTab extends StatelessWidget {
  const _FrequencyTab({
    required this.report,
    required this.running,
    required this.onRun,
  });

  final BiasAuditReport? report;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return _EmptyState(running: running, onRun: onRun);
    }
    final r = report!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        SectionCard(
          title: '這部機器均勻嗎？',
          subtitle:
              '每顆球的 Dirichlet-multinomial 後驗、卡方整體檢定，'
              '以及 Sanov 大偏差上界。這是關於攪珠機唯一可用數據回答的問題——'
              '而它跟「下期開邊個號」並不是同一條問題。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatWrap(
                children: <Widget>[
                  StatTile(label: '期數', value: r.draws.toString()),
                  StatTile(label: '球號觀測數', value: r.observations.toString()),
                  StatTile(
                    label: '卡方（自由度 48）',
                    value: r.chiSquare.toStringAsFixed(1),
                    hint: '漸近 p = ${r.chiSquareP.toStringAsFixed(3)}',
                  ),
                  StatTile(
                    label: '蒙地卡羅 p',
                    value: r.monteCarloP.toStringAsFixed(3),
                    emphasis: true,
                    color: r.significantAtFivePercent ? kDanger : kAccent,
                    hint: r.significantAtFivePercent ? '偵測到偏離' : '與公平機器一致',
                  ),
                  StatTile(
                    label: '與均勻分佈的 KL',
                    value: r.klDivergence.toStringAsExponential(2),
                    hint: '每次觀測的 nats',
                  ),
                  StatTile(
                    label: 'Sanov 上界',
                    value: '1e${r.log10SanovBound.toStringAsFixed(1)}',
                    hint: 'exp(-n·KL)：機器公平時出現這麼大偏離的機會',
                  ),
                  StatTile(
                    label: '最極端的球',
                    value: '#${r.extreme.number}',
                    hint:
                        'z = ${r.extreme.zScore.toStringAsFixed(2)}，'
                        '偏離均勻 ${(r.extreme.relativeDeviation * 100).toStringAsFixed(1)}%',
                  ),
                  StatTile(
                    label: 'Bonferroni p',
                    value: r.bonferroniP.toStringAsFixed(3),
                    hint: '已針對同時看 49 顆球作修正',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                '各球號的標準化偏離',
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
              const SizedBox(height: 8),
              BarChart(
                values: r.posteriors.map((p) => p.zScore).toList(),
                threshold: 2.79,
              ),
              const SizedBox(height: 6),
              const Text(
                '虛線為 49 顆球經 Bonferroni 修正後的 5% 門檻（|z| = 2.79）。'
                '越過門檻的只是候選，不是結論。',
                style: TextStyle(fontSize: 11, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '後驗可信區間',
          subtitle:
              '均勻機率為 1/49 = ${(1 / kBallCount).toStringAsFixed(5)}。'
              '區間只以期數的平方根收窄，所以要分辨百分之幾的偏差需要幾百年。',
          child: Column(
            children:
                (List<BallPosterior>.of(
                      r.posteriors,
                    )..sort((a, b) => b.zScore.abs().compareTo(a.zScore.abs())))
                    .take(8)
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            BallChip(number: p.number, size: 34),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '出現 ${p.count} 次 · 後驗均值 '
                                '${p.posteriorMean.toStringAsFixed(5)} · 95% 區間 ['
                                '${p.lower95.toStringAsFixed(5)}, '
                                '${p.upper95.toStringAsFixed(5)}]',
                                style: kMonoStyle.copyWith(fontSize: 12),
                              ),
                            ),
                            Text(
                              'z ${p.zScore.toStringAsFixed(2)}',
                              style: kMonoStyle.copyWith(
                                fontSize: 12,
                                color: p.zScore.abs() > 2.79 ? kDanger : kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _RmtTab extends StatelessWidget {
  const _RmtTab({
    required this.report,
    required this.running,
    required this.onRun,
  });

  final RmtReport? report;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return _EmptyState(running: running, onRun: onRun);
    }
    final r = report!;
    final poisson = <Offset>[];
    final wigner = <Offset>[];
    for (var i = 0; i <= 160; i++) {
      final s = i * 4 / 160;
      poisson.add(Offset(s, poissonSpacingPdf(s)));
      wigner.add(Offset(s, wignerSpacingPdf(s)));
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.blur_linear,
          text:
              '把每期開獎當成 49 個能階中被佔用的 6 個能階。若各球獨立跌出，'
              '間距應為 Poisson 分佈 exp(-s)；若某球跌出會壓抑鄰近球號，'
              '間距就會出現「能階排斥」，服從隨機矩陣理論的 Wigner 猜測。'
              '據我所知這個檢定從未用在彩票上，即使結果是「無異常」也是第一次。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '最近鄰間距分佈',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              HistogramWithCurves(
                samples: r.spacings,
                curves: <Series>[
                  Series(
                    points: poisson,
                    color: kAccentWarm,
                    label: 'Poisson exp(-s)',
                  ),
                  Series(points: wigner, color: kDanger, label: 'Wigner GOE'),
                ],
              ),
              const SizedBox(height: 16),
              StatWrap(
                children: <Widget>[
                  StatTile(label: '期數', value: r.draws.toString()),
                  StatTile(label: '間距數目', value: r.spacings.length.toString()),
                  StatTile(
                    label: 'KS（對 Poisson）',
                    value: r.ksPoisson.toStringAsFixed(4),
                    hint: '校準 p = ${r.ksPoissonP.toStringAsFixed(3)}',
                  ),
                  StatTile(
                    label: 'KS（對 Wigner）',
                    value: r.ksWigner.toStringAsFixed(4),
                  ),
                  StatTile(
                    label: 'log 貝氏因子',
                    value: r.logBayesFactorWignerOverPoisson.toStringAsFixed(1),
                    hint: 'Wigner 對 Poisson',
                    emphasis: true,
                    color: r.favoursRepulsion ? kDanger : kAccent,
                  ),
                  StatTile(
                    label: '校準後 p',
                    value: r.monteCarloPForBayesFactor.toStringAsFixed(3),
                    hint: '對照模擬的公平開獎',
                  ),
                  StatTile(
                    label: '平均間距',
                    value: r.meanSpacing.toStringAsFixed(3),
                    hint: '按定義已正規化為 1',
                  ),
                  StatTile(
                    label: '間距變異數',
                    value: r.varianceSpacing.toStringAsFixed(3),
                    hint: 'Poisson 預測 1，Wigner 預測 0.27',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InfoBanner(
                color: r.favoursRepulsion ? kDanger : kAccent,
                icon: r.favoursRepulsion
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
                text: r.favoursRepulsion
                    ? '在模擬虛無分佈之外仍支持能階排斥。相信之前，值得用另一份資料再驗一次。'
                    : '除了「公平不放回抽樣」本身造成的結構之外，沒有額外結構。'
                          '因為 49 選 6 是離散的，原始貝氏因子在這裡會誤導，'
                          '只有校準後的 p 值才有意義。',
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _MixingTab extends StatelessWidget {
  const _MixingTab({
    required this.report,
    required this.running,
    required this.onRun,
  });

  final MixingReport? report;
  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    if (report == null) {
      return _EmptyState(running: running, onRun: onRun);
    }
    final r = report!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.link,
          text:
              '球通常按號碼順序裝入，所以初始狀態的熵是零。如果攪拌時間短於混合時間，'
              '殘留的並不會是「熱門號碼」，而是與裝球順序距離相關的結構。'
              '這是另一條可否證的假說，也正是靠頻率統計的 App 從來不檢驗的一條。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '相鄰性檢定',
          subtitle:
              '精確虛無假設：P(沒有相鄰號碼) = C(44,6)/C(49,6) = '
              '${(nonAdjacentSubsetCount(kBallCount, kPickCount) / kTotalCombinations).toStringAsFixed(4)}.',
          child: StatWrap(
            children: <Widget>[
              StatTile(
                label: '出現相鄰號碼的期數',
                value:
                    '${r.adjacency.observedWithAdjacent} / ${r.adjacency.draws}',
              ),
              StatTile(
                label: '理論比例',
                value:
                    '${(r.adjacency.expectedProbability * 100).toStringAsFixed(2)}%',
              ),
              StatTile(
                label: 'z',
                value: r.adjacency.zScore.toStringAsFixed(2),
              ),
              StatTile(
                label: 'p',
                value: r.adjacency.pValue.toStringAsFixed(3),
                color: r.adjacency.pValue < 0.05 ? kDanger : kAccent,
                emphasis: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '裝球順序自相關 C(k)',
          subtitle:
              '沿裝球順序在間隔 k 上的佔用相關，虛無均值與離散度由模擬公平開獎取得。'
              '整族 p = ${r.familywiseP.toStringAsFixed(3)}。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              BarChart(
                values: r.autocorrelations.map((a) => a.zScore).toList(),
                threshold: 2.5,
                labelEvery: 1,
              ),
              const SizedBox(height: 12),
              ...r.autocorrelations.map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '間隔 ${a.lag.toString().padLeft(2)} · C = '
                    '${a.correlation.toStringAsExponential(2)} · z = '
                    '${a.zScore.toStringAsFixed(2)} · p = '
                    '${a.pValue.toStringAsFixed(3)}',
                    style: kMonoStyle.copyWith(
                      fontSize: 12,
                      color: a.pValue * r.autocorrelations.length < 0.05
                          ? kDanger
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InfoBanner(
                color: r.anyResidualStructure ? kDanger : kAccent,
                icon: r.anyResidualStructure
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
                text: r.anyResidualStructure
                    ? '裝球順序的殘留結構在多重檢定修正後仍然存在。這會是真正的發現——'
                          '但仍然不足以讓任何人預測開獎。'
                    : '沒有裝球順序的殘留記憶，與「攪拌時間遠長於混合時間」一致。',
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _PowerTab extends StatefulWidget {
  const _PowerTab({required this.availableDraws});

  final int availableDraws;

  @override
  State<_PowerTab> createState() => _PowerTabState();
}

class _PowerTabState extends State<_PowerTab> {
  double _bias = 0.05;
  double _massDefect = 1e-3;
  double _kappa = 3;

  @override
  Widget build(BuildContext context) {
    final r = PowerAnalysis.forRelativeBias(
      relativeBias: _bias,
      availableDraws: widget.availableDraws,
    );
    final physicsBias = biasFromMassDefect(
      relativeMassDefect: _massDefect,
      kappa: _kappa,
    );
    final physicsPower = PowerAnalysis.forRelativeBias(
      relativeBias: physicsBias.abs(),
      availableDraws: widget.availableDraws,
    );

    final curve = <Offset>[];
    for (var i = 1; i <= 60; i++) {
      final e = i * 0.01;
      final res = PowerAnalysis.forRelativeBias(
        relativeBias: e,
        availableDraws: widget.availableDraws,
      );
      curve.add(Offset(e * 100, math.log(res.requiredYears) / math.ln10));
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.hourglass_bottom,
          color: kDanger,
          text:
              '這是終結爭論的計算。物理上，印墨質量與直徑公差容許約 0.1% 量級的偏差；'
              '統計則告訴你要多少期才能辨認出來。兩個數字在人的一生內完全不重疊——'
              '所以「沒有可利用的偏差」是可以證明的，而不只是很可能。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '指定偏差的可偵測性',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: '單一球號的相對偏差',
                value: _bias,
                min: 0.005,
                max: 0.5,
                display: '${(_bias * 100).toStringAsFixed(1)}%',
                onChanged: (v) => setState(() => _bias = v),
              ),
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: '所需期數',
                    value: r.requiredDraws.toStringAsFixed(0),
                    hint: '80% 檢定力，並對 49 顆球作 Bonferroni 修正',
                    emphasis: true,
                  ),
                  StatTile(
                    label: '所需年數',
                    value: r.requiredYears.toStringAsFixed(0),
                    hint: '以每年 152 期計',
                    emphasis: true,
                    color: kDanger,
                  ),
                  StatTile(
                    label: '以 ${r.availableDraws} 期的檢定力',
                    value: '${(r.achievedPower * 100).toStringAsFixed(1)}%',
                  ),
                  StatTile(
                    label: '現在能偵測的偏差',
                    value:
                        '${(r.detectableEffectAtAvailable * 100).toStringAsFixed(1)}%',
                    hint: '以這份資料能看見的最小效應',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LineChart(
                series: <Series>[
                  Series(points: curve, color: kDanger, label: 'log10 所需年數'),
                ],
                xLabel: '相對偏差（%）',
                height: 200,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '由工程公差到機率',
          subtitle:
              '最大熵橋樑：δP/P = -κ · δm/m。氣流式攪珠機的 κ 比重力滾筒大，'
              '因為較輕的球更容易被吹起。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: '相對質量差 δm/m（印墨、雕刻、公差）',
                value: math.log(_massDefect) / math.ln10,
                min: -5,
                max: -1.5,
                display: _massDefect.toStringAsExponential(1),
                onChanged: (v) =>
                    setState(() => _massDefect = math.pow(10, v).toDouble()),
              ),
              LabeledSlider(
                label: '機器敏感度 κ',
                value: _kappa,
                min: 0.5,
                max: 12,
                display: _kappa.toStringAsFixed(1),
                onChanged: (v) => setState(() => _kappa = v),
              ),
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: '推得的機率偏差',
                    value: '${(physicsBias * 100).toStringAsFixed(3)}%',
                    emphasis: true,
                  ),
                  StatTile(
                    label: '偵測所需期數',
                    value: physicsPower.requiredDraws.toStringAsExponential(2),
                  ),
                  StatTile(
                    label: '偵測所需年數',
                    value: physicsPower.requiredYears.toStringAsExponential(2),
                    color: kDanger,
                    emphasis: true,
                  ),
                  StatTile(
                    label: '目前檢定力',
                    value:
                        '${(physicsPower.achievedPower * 100).toStringAsFixed(2)}%',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.running, required this.onRun});

  final bool running;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.query_stats, size: 42, color: kMuted),
          const SizedBox(height: 12),
          const Text('尚未有結果。', style: TextStyle(color: kMuted, fontSize: 13)),
          const SizedBox(height: 16),
          _RunBar(running: running, onRun: onRun),
        ],
      ),
    );
  }
}
