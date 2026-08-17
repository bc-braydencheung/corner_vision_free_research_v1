import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../lab_state.dart';
import '../core/combinatorics.dart';
import '../core/drbg.dart';
import '../crowd/calibration.dart';
import '../crowd/crowd_model.dart';
import '../crowd/optimizer.dart';
import '../crowd/parimutuel.dart';
import 'theme.dart';
import 'widgets/panels.dart';

class CrowdPage extends StatefulWidget {
  const CrowdPage({super.key, required this.state});

  final LabState state;

  @override
  State<CrowdPage> createState() => _CrowdPageState();
}

class _CrowdPageState extends State<CrowdPage> {
  List<RareCombination> _results = <RareCombination>[];
  CalibrationResult? _calibration;
  String? _calibrationError;
  String? _searchError;
  bool _busy = false;
  double _pool = 8.0e7;
  double _units = 3.0e7;
  final Set<int> _excluded = <int>{};

  Future<void> _optimise() async {
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final optimizer = AntiCrowdOptimizer(
      widget.state.crowdModel,
      widget.state.rarityScale,
    );
    final rng = Drbg(<int>[
      ...DateTime.now().microsecondsSinceEpoch.toRadixString(16).codeUnits,
    ]);
    List<RareCombination> results;
    String? error;
    try {
      results = optimizer.search(rng: rng, results: 6, excluded: _excluded);
    } on ArgumentError {
      results = <RareCombination>[];
      error = '排除太多號碼：至少要留下 6 個可選。';
    }
    if (!mounted) return;
    setState(() {
      _results = results;
      _searchError = error;
      _busy = false;
    });
  }

  Future<void> _calibrate() async {
    setState(() {
      _busy = true;
      _calibrationError = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      final result = CrowdCalibration.fit(widget.state.history);
      widget.state.setCrowdWeights(result.weights, intercept: result.intercept);
      if (!mounted) return;
      setState(() {
        _calibration = result;
        _busy = false;
      });
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _calibrationError = e.message.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final model = state.crowdModel;
    final scale = state.rarityScale;

    final examples = <String, List<int>>{
      '生日選號': <int>[3, 7, 12, 18, 24, 31],
      '等差數列': <int>[5, 10, 15, 20, 25, 30],
      '連號 1-6': <int>[1, 2, 3, 4, 5, 6],
      '總和約 150': <int>[8, 17, 23, 31, 36, 43],
      '大號兼忌諱號': <int>[4, 14, 34, 41, 44, 47],
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.groups_outlined,
          text:
              '這是物理上唯一留下來的槓桿。六合彩是同注分彩：'
              'E[派彩 | c] = 獎金 · P(中獎) / (1 + N·q(c))。P(中獎) 對每個組合都一樣，'
              '並且無法提升；但大眾選中 c 的機率 q(c) 可以相差幾個量級——'
              '所以用沒人選的組合中獎，同一筆獎金可以值幾倍。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '最冷門的組合',
          subtitle:
              '在 C(49,6) 上用模擬退火最小化 q(c)。以當前時鐘作種子，'
              '避免大家拿到同一組「冷門」號碼，反而造出新的人群。',
          trailing: FilledButton.icon(
            onPressed: _busy ? null : _optimise,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.trending_down),
            label: const Text('搜尋'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_searchError != null)
                InfoBanner(
                  text: _searchError!,
                  color: kDanger,
                  icon: Icons.error_outline,
                ),
              if (_results.isEmpty && _searchError == null)
                const Text(
                  '按「搜尋」看候選組合。',
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
              ..._results.map((r) {
                final outcome = evaluateParimutuel(
                  pool: _pool,
                  unitsSold: _units,
                  crowdRatio: r.crowdRatio,
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: r.numbers
                            .map((n) => BallChip(number: n, size: 38))
                            .toList(growable: false),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '冷門度 ${(r.rarityPercentile * 100).toStringAsFixed(1)}% · '
                        'q/q̄ ${r.crowdRatio.toStringAsFixed(3)} · 預期分帳人數 '
                        '${outcome.expectedCoWinners.toStringAsFixed(3)} · 頭獎期望值比平均選號高 '
                        '${((outcome.improvementRatio - 1) * 100).toStringAsFixed(1)}%',
                        style: kMonoStyle.copyWith(
                          fontSize: 11.5,
                          color: kMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              LabeledSlider(
                label: '假設頭獎基金（港元）',
                value: _pool,
                min: 8.0e6,
                max: 5.0e8,
                display: '${(_pool / 1e6).toStringAsFixed(0)}M',
                onChanged: (v) => setState(() => _pool = v),
              ),
              LabeledSlider(
                label: '假設總投注注數',
                value: _units,
                min: 5.0e6,
                max: 1.5e8,
                display: '${(_units / 1e6).toStringAsFixed(0)}M',
                onChanged: (v) => setState(() => _units = v),
              ),
              const SizedBox(height: 8),
              Text(
                '在這些假設下，每注 10 元的 Kelly 比例為 '
                '${kellyFraction(p: 1 / kTotalCombinations, netOdds: _pool / 10).toStringAsExponential(2)}'
                '——負數，數學上正確的指示就是：不要下注。',
                style: const TextStyle(fontSize: 12, color: kDanger),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '常見選號的熱門程度',
          subtitle: '這些組合中獎的頻率跟任何其他組合完全相同，差別只在於要與多少人分帳。',
          child: Column(
            children: examples.entries
                .map((e) {
                  final score = model.logPopularity(e.value);
                  final ratio = scale.crowdRatio(score);
                  final pct = scale.percentileForScore(score);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 150,
                          child: Text(
                            e.key,
                            style: const TextStyle(fontSize: 12, color: kMuted),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.value.join(' · '),
                            style: kMonoStyle.copyWith(fontSize: 12),
                          ),
                        ),
                        Text(
                          'q/q̄ ${ratio.toStringAsFixed(2)} · '
                          '冷門度 ${(pct * 100).toStringAsFixed(0)}%',
                          style: kMonoStyle.copyWith(
                            fontSize: 11.5,
                            color: ratio > 1.5 ? kDanger : kAccent,
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '由公佈中獎注數校準 q(c)',
          subtitle:
              '這是逆問題：中獎組合本身是全空間的均勻隨機樣本，'
              '所以把頭獎中獎注數對組合特征做回歸，就能得到人群偏好曲面的無偏估計。'
              '泊松回歸：y ~ Poisson(exp(a + w·f))。',
          trailing: FilledButton.tonalIcon(
            onPressed: _busy ? null : _calibrate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('擬合'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (_calibrationError != null)
                InfoBanner(
                  text: _calibrationError!,
                  color: kDanger,
                  icon: Icons.error_outline,
                ),
              if (_calibration != null) ...<Widget>[
                StatWrap(
                  children: <Widget>[
                    StatTile(
                      label: '使用期數',
                      value: _calibration!.observations.toString(),
                    ),
                    StatTile(
                      label: '對均勻人群的偏差度',
                      value: _calibration!.deviance.toStringAsFixed(1),
                      hint: '自由度 ${_calibration!.degreesOfFreedom}',
                    ),
                    StatTile(
                      label: 'p 值',
                      value: _calibration!.pValue.toStringAsExponential(2),
                      emphasis: true,
                      color: _calibration!.pValue < 0.05 ? kAccent : kMuted,
                      hint: _calibration!.pValue < 0.05
                          ? '人群偏好可測得到，並非均勻'
                          : '偵測不到人群結構',
                    ),
                    StatTile(
                      label: '迭代次數',
                      value: _calibration!.iterations.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              ...CrowdFeature.values.map((f) {
                final w = model.weights[f] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 190,
                        child: Text(
                          _featureLabel(f),
                          style: const TextStyle(fontSize: 12, color: kMuted),
                        ),
                      ),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (w.abs() / 1.2).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: kSurfaceAlt,
                          color: w >= 0 ? kAccentWarm : kAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 66,
                        child: Text(
                          w.toStringAsFixed(3),
                          textAlign: TextAlign.right,
                          style: kMonoStyle.copyWith(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () {
                      state.resetCrowdWeights();
                      setState(() => _calibration = null);
                    },
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('回到先驗值'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '排除號碼',
          subtitle: '不詖你什麼理由，你不選的號碼，優化器都會遵守。',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (var n = 1; n <= kBallCount; n++)
                GestureDetector(
                  onTap: () => setState(() {
                    if (!_excluded.remove(n)) _excluded.add(n);
                  }),
                  child: Opacity(
                    opacity: _excluded.contains(n) ? 0.28 : 1,
                    child: BallChip(number: n, size: 32),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  String _featureLabel(CrowdFeature f) {
    switch (f) {
      case CrowdFeature.birthdayNumbers:
        return '1-31（生日）';
      case CrowdFeature.monthNumbers:
        return '1-12（月份）';
      case CrowdFeature.luckyNumbers:
        return '吉利數字';
      case CrowdFeature.unluckyNumbers:
        return '忌諱數字（4、14、…）';
      case CrowdFeature.consecutiveRun:
        return '連號';
      case CrowdFeature.arithmeticProgression:
        return '等差數列';
      case CrowdFeature.multiplesOfFive:
        return '五的倍數';
      case CrowdFeature.sameLastDigit:
        return '尾數重複';
      case CrowdFeature.sumCentrality:
        return '總和接近 150';
      case CrowdFeature.gridLineConcentration:
        return '注單的行與列';
      case CrowdFeature.evenGapSpread:
        return '號碼均勻分佈';
      case CrowdFeature.repeatFromLastDraw:
        return '重複上期號碼';
    }
  }
}

/// Exposed for tests: the sum used by the rarity histogram.
double meanOf(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

double stdDevOf(List<double> values) {
  if (values.length < 2) return 0;
  final m = meanOf(values);
  var v = 0.0;
  for (final x in values) {
    v += math.pow(x - m, 2).toDouble();
  }
  return math.sqrt(v / (values.length - 1));
}
