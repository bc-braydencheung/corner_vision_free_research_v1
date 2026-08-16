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
      error = 'Too many numbers excluded: keep at least 6 playable.';
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
      'birthday pick': <int>[3, 7, 12, 18, 24, 31],
      'arithmetic run': <int>[5, 10, 15, 20, 25, 30],
      'straight line 1-6': <int>[1, 2, 3, 4, 5, 6],
      'balanced sum ~150': <int>[8, 17, 23, 31, 36, 43],
      'high and unlucky': <int>[4, 14, 34, 41, 44, 47],
    };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.groups_outlined,
          text:
              'The only lever that survives the physics. Mark Six is '
              'parimutuel: E[payout | c] = Pool · P(win) / (1 + N·q(c)). P(win) is '
              'the same for every combination and cannot be improved. q(c), the '
              'probability the crowd picks c, varies by orders of magnitude - so '
              'the same jackpot is worth several times more when won with a '
              'combination nobody else plays.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Rarest combinations',
          subtitle:
              'Simulated annealing over C(49,6) minimising q(c). Seeded '
              'from the current clock so the advice does not create a new crowd '
              'by handing everyone the same "rare" ticket.',
          trailing: FilledButton.icon(
            onPressed: _busy ? null : _optimise,
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.trending_down),
            label: const Text('Search'),
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
                  'Run a search to see candidates.',
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
                        'rarity ${(r.rarityPercentile * 100).toStringAsFixed(1)}% · '
                        'q/q̄ ${r.crowdRatio.toStringAsFixed(3)} · expected '
                        'co-winners ${outcome.expectedCoWinners.toStringAsFixed(3)} · '
                        'division-1 EV '
                        '${((outcome.improvementRatio - 1) * 100).toStringAsFixed(1)}% '
                        'above an average pick',
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
                label: 'assumed division-1 pool (HKD)',
                value: _pool,
                min: 8.0e6,
                max: 5.0e8,
                display: '${(_pool / 1e6).toStringAsFixed(0)}M',
                onChanged: (v) => setState(() => _pool = v),
              ),
              LabeledSlider(
                label: 'assumed units sold',
                value: _units,
                min: 5.0e6,
                max: 1.5e8,
                display: '${(_units / 1e6).toStringAsFixed(0)}M',
                onChanged: (v) => setState(() => _units = v),
              ),
              const SizedBox(height: 8),
              Text(
                'Kelly fraction for a HKD 10 unit at these assumptions: '
                '${kellyFraction(p: 1 / kTotalCombinations, netOdds: _pool / 10).toStringAsExponential(2)} '
                '- negative, which is the mathematically correct instruction: '
                'stake nothing.',
                style: const TextStyle(fontSize: 12, color: kDanger),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Popularity of familiar picks',
          subtitle:
              'Every one of these wins exactly as often as any other '
              'combination. They differ only in how many people you would split '
              'with.',
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
                          'rarity ${(pct * 100).toStringAsFixed(0)}%',
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
          title: 'Calibrate q(c) from published winner counts',
          subtitle:
              'The inverse problem: winning combinations are a uniform '
              'random sample of the space, so regressing division-1 winning units '
              'on combination features gives an unbiased estimate of the crowd\'s '
              'preference surface. Poisson regression, y ~ Poisson(exp(a + w·f)).',
          trailing: FilledButton.tonalIcon(
            onPressed: _busy ? null : _calibrate,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Fit'),
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
                      label: 'draws used',
                      value: _calibration!.observations.toString(),
                    ),
                    StatTile(
                      label: 'deviance vs uniform crowd',
                      value: _calibration!.deviance.toStringAsFixed(1),
                      hint: '${_calibration!.degreesOfFreedom} df',
                    ),
                    StatTile(
                      label: 'p-value',
                      value: _calibration!.pValue.toStringAsExponential(2),
                      emphasis: true,
                      color: _calibration!.pValue < 0.05 ? kAccent : kMuted,
                      hint: _calibration!.pValue < 0.05
                          ? 'the crowd is measurably non-uniform'
                          : 'no detectable crowd structure',
                    ),
                    StatTile(
                      label: 'iterations',
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
                    label: const Text('Reset to priors'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Exclude numbers',
          subtitle:
              'Numbers you refuse to play, for any reason. The optimiser '
              'respects the constraint.',
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
        return 'numbers 1-31 (birthdays)';
      case CrowdFeature.monthNumbers:
        return 'numbers 1-12 (months)';
      case CrowdFeature.luckyNumbers:
        return 'lucky numbers';
      case CrowdFeature.unluckyNumbers:
        return 'avoided numbers (4, 14, …)';
      case CrowdFeature.consecutiveRun:
        return 'consecutive runs';
      case CrowdFeature.arithmeticProgression:
        return 'arithmetic progression';
      case CrowdFeature.multiplesOfFive:
        return 'multiples of five';
      case CrowdFeature.sameLastDigit:
        return 'repeated last digit';
      case CrowdFeature.sumCentrality:
        return 'sum near 150';
      case CrowdFeature.gridLineConcentration:
        return 'bet-slip rows and columns';
      case CrowdFeature.evenGapSpread:
        return 'evenly spread numbers';
      case CrowdFeature.repeatFromLastDraw:
        return 'repeats from last draw';
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
