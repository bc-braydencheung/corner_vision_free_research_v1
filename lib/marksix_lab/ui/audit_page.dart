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
              Tab(text: 'Dataset'),
              Tab(text: 'Ball frequencies'),
              Tab(text: 'Level spacing (RMT)'),
              Tab(text: 'Mixing structure'),
              Tab(text: 'Statistical power'),
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
          label: Text(running ? 'Running Monte Carlo…' : 'Run audit'),
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
        () => _importMessage =
            'No valid rows found. ${result.errors.take(3).join('; ')}',
      );
      return;
    }
    widget.state.setImportedHistory(
      result.draws,
      'Imported ${result.draws.length} draws'
      '${result.errors.isEmpty ? '' : ', ${result.errors.length} row(s) skipped'}.',
    );
    setState(
      () => _importMessage =
          'Imported ${result.draws.length} draws. Skipped ${result.errors.length}.',
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
          title: 'Controlled experiment',
          subtitle:
              'The bundled dataset is synthetic on purpose. Inject a known '
              'bias on one ball, then run the audit and see whether it can be '
              'found with the number of draws a real lifetime provides.',
          child: Column(
            children: <Widget>[
              LabeledSlider(
                label: 'number of draws',
                value: state.syntheticDraws.toDouble(),
                min: 200,
                max: 6000,
                divisions: 29,
                display: state.syntheticDraws.toString(),
                onChanged: (v) =>
                    state.configureSynthetic(draws: (v / 200).round() * 200),
              ),
              LabeledSlider(
                label: 'biased ball',
                value: (state.injectedBiasBall ?? 1).toDouble(),
                min: 1,
                max: kBallCount.toDouble(),
                divisions: kBallCount - 1,
                display: state.injectedBiasBall?.toString() ?? 'none',
                onChanged: (v) =>
                    state.configureSynthetic(biasedBall: v.round()),
              ),
              LabeledSlider(
                label: 'injected relative bias',
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
                    label: const Text('Fair machine'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => state.regenerateSynthetic(newSeed: true),
                    icon: const Icon(Icons.casino_outlined),
                    label: const Text('Resample'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Import real results',
          subtitle:
              'Paste the published record as '
              'label,date,n1..n6[,extra][,division-1 winning units]. Winner '
              'counts unlock the crowd-model calibration.',
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
                    label: const Text('Import'),
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
          title: 'Run',
          subtitle:
              'All three tests use Monte Carlo nulls under exact '
              'without-replacement sampling, not asymptotic approximations.',
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
          title: 'Is the machine uniform?',
          subtitle:
              'Dirichlet-multinomial posteriors per ball, a chi-square '
              'omnibus test, and Sanov\'s large-deviation bound. This is the only '
              'empirically answerable question about a lottery machine - and it is '
              'not the same question as "which number is next".',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatWrap(
                children: <Widget>[
                  StatTile(label: 'draws', value: r.draws.toString()),
                  StatTile(
                    label: 'ball observations',
                    value: r.observations.toString(),
                  ),
                  StatTile(
                    label: 'chi-square (48 df)',
                    value: r.chiSquare.toStringAsFixed(1),
                    hint: 'asymptotic p = ${r.chiSquareP.toStringAsFixed(3)}',
                  ),
                  StatTile(
                    label: 'Monte Carlo p',
                    value: r.monteCarloP.toStringAsFixed(3),
                    emphasis: true,
                    color: r.significantAtFivePercent ? kDanger : kAccent,
                    hint: r.significantAtFivePercent
                        ? 'deviation detected'
                        : 'consistent with a fair machine',
                  ),
                  StatTile(
                    label: 'KL from uniform',
                    value: r.klDivergence.toStringAsExponential(2),
                    hint: 'nats per observation',
                  ),
                  StatTile(
                    label: 'Sanov bound',
                    value: '1e${r.log10SanovBound.toStringAsFixed(1)}',
                    hint: 'exp(-n·KL): chance of this much deviation if fair',
                  ),
                  StatTile(
                    label: 'most extreme ball',
                    value: '#${r.extreme.number}',
                    hint:
                        'z = ${r.extreme.zScore.toStringAsFixed(2)}, '
                        '${(r.extreme.relativeDeviation * 100).toStringAsFixed(1)}% off uniform',
                  ),
                  StatTile(
                    label: 'Bonferroni p',
                    value: r.bonferroniP.toStringAsFixed(3),
                    hint: 'corrected for looking at all 49 balls',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Standardised deviation per ball',
                style: TextStyle(fontSize: 12, color: kMuted),
              ),
              const SizedBox(height: 8),
              BarChart(
                values: r.posteriors.map((p) => p.zScore).toList(),
                threshold: 2.79,
              ),
              const SizedBox(height: 6),
              const Text(
                'Dashed lines: Bonferroni-corrected 5% threshold across 49 balls '
                '(|z| = 2.79). Bars crossing it are candidates, not conclusions.',
                style: TextStyle(fontSize: 11, color: kMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Posterior credible intervals',
          subtitle:
              'Uniform rate is 1/49 = ${(1 / kBallCount).toStringAsFixed(5)}. '
              'Intervals shrink as the square root of the number of draws, which '
              'is why centuries are needed to resolve a percent-level bias.',
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
                                'count ${p.count} · mean '
                                '${p.posteriorMean.toStringAsFixed(5)} · 95% CI ['
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
              'Each draw is read as six occupied levels in a 49-level '
              'spectrum. Independent releases give Poisson spacings, exp(-s). If '
              'releasing one ball suppressed its neighbours, the spacings would '
              'show level repulsion and follow the Wigner surmise from random '
              'matrix theory. As far as I know this test has never been applied '
              'to a lottery; a null result is still the first one.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Nearest-neighbour spacing distribution',
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
                  StatTile(label: 'draws', value: r.draws.toString()),
                  StatTile(
                    label: 'spacings',
                    value: r.spacings.length.toString(),
                  ),
                  StatTile(
                    label: 'KS vs Poisson',
                    value: r.ksPoisson.toStringAsFixed(4),
                    hint: 'calibrated p = ${r.ksPoissonP.toStringAsFixed(3)}',
                  ),
                  StatTile(
                    label: 'KS vs Wigner',
                    value: r.ksWigner.toStringAsFixed(4),
                  ),
                  StatTile(
                    label: 'log Bayes factor',
                    value: r.logBayesFactorWignerOverPoisson.toStringAsFixed(1),
                    hint: 'Wigner over Poisson',
                    emphasis: true,
                    color: r.favoursRepulsion ? kDanger : kAccent,
                  ),
                  StatTile(
                    label: 'calibrated p',
                    value: r.monteCarloPForBayesFactor.toStringAsFixed(3),
                    hint: 'against simulated fair draws',
                  ),
                  StatTile(
                    label: 'mean spacing',
                    value: r.meanSpacing.toStringAsFixed(3),
                    hint: 'normalised to 1 by construction',
                  ),
                  StatTile(
                    label: 'spacing variance',
                    value: r.varianceSpacing.toStringAsFixed(3),
                    hint: 'Poisson predicts 1, Wigner 0.27',
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
                    ? 'Level repulsion favoured beyond the simulated null. Worth '
                          'a second dataset before believing it.'
                    : 'No structure beyond what fair without-replacement '
                          'sampling produces by itself. The raw Bayes factor is '
                          'misleading here because a 6-of-49 draw is discrete: only '
                          'the calibrated p-value is meaningful.',
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
              'The balls are loaded in numerical order, so the initial state '
              'has zero entropy. If stirring were shorter than the mixing time, '
              'the residue would not be "hot numbers" - it would be structure in '
              'loading-order distance. That is a different, falsifiable '
              'hypothesis, and it is the one the frequency-based apps never test.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Adjacency test',
          subtitle:
              'Exact null: P(no adjacent pair) = C(44,6)/C(49,6) = '
              '${(nonAdjacentSubsetCount(kBallCount, kPickCount) / kTotalCombinations).toStringAsFixed(4)}.',
          child: StatWrap(
            children: <Widget>[
              StatTile(
                label: 'draws with an adjacent pair',
                value:
                    '${r.adjacency.observedWithAdjacent} / ${r.adjacency.draws}',
              ),
              StatTile(
                label: 'expected share',
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
          title: 'Loading-order autocorrelation C(k)',
          subtitle:
              'Occupancy correlation at lag k along the loading order, '
              'with the null mean and spread obtained by simulating fair draws. '
              'Family-wise p = ${r.familywiseP.toStringAsFixed(3)}.',
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
                    'lag ${a.lag.toString().padLeft(2)} · C = '
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
                    ? 'Residual loading-order structure survives multiple-testing '
                          'correction. This would be a real finding - and it would '
                          'still not let anyone predict a draw.'
                    : 'No residual memory of the loading order. Consistent with '
                          'stirring for much longer than the mixing time.',
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
              'The calculation that ends the argument. Physics allows a bias of '
              'order 0.1% from ink mass and diameter tolerances. Statistics says '
              'how many draws are needed to identify it. The two numbers do not '
              'overlap in a human lifetime - so the absence of exploitable bias '
              'is provable, not merely likely.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Detectability of a chosen bias',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: 'relative bias on one ball',
                value: _bias,
                min: 0.005,
                max: 0.5,
                display: '${(_bias * 100).toStringAsFixed(1)}%',
                onChanged: (v) => setState(() => _bias = v),
              ),
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: 'draws required',
                    value: r.requiredDraws.toStringAsFixed(0),
                    hint: '80% power, Bonferroni across 49 balls',
                    emphasis: true,
                  ),
                  StatTile(
                    label: 'years required',
                    value: r.requiredYears.toStringAsFixed(0),
                    hint: 'at 152 draws per year',
                    emphasis: true,
                    color: kDanger,
                  ),
                  StatTile(
                    label: 'power with ${r.availableDraws} draws',
                    value: '${(r.achievedPower * 100).toStringAsFixed(1)}%',
                  ),
                  StatTile(
                    label: 'detectable bias today',
                    value:
                        '${(r.detectableEffectAtAvailable * 100).toStringAsFixed(1)}%',
                    hint: 'smallest effect visible with this dataset',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LineChart(
                series: <Series>[
                  Series(
                    points: curve,
                    color: kDanger,
                    label: 'log10 years needed',
                  ),
                ],
                xLabel: 'relative bias (%)',
                height: 200,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'From engineering tolerance to probability',
          subtitle:
              'Maximum-entropy link: dP/P = -kappa · dm/m. Air-blower '
              'machines have larger kappa than gravity drums because a lighter '
              'ball is lifted more easily.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LabeledSlider(
                label: 'relative mass defect dm/m (ink, engraving, tolerance)',
                value: math.log(_massDefect) / math.ln10,
                min: -5,
                max: -1.5,
                display: _massDefect.toStringAsExponential(1),
                onChanged: (v) =>
                    setState(() => _massDefect = math.pow(10, v).toDouble()),
              ),
              LabeledSlider(
                label: 'machine sensitivity kappa',
                value: _kappa,
                min: 0.5,
                max: 12,
                display: _kappa.toStringAsFixed(1),
                onChanged: (v) => setState(() => _kappa = v),
              ),
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: 'implied probability bias',
                    value: '${(physicsBias * 100).toStringAsFixed(3)}%',
                    emphasis: true,
                  ),
                  StatTile(
                    label: 'draws to detect it',
                    value: physicsPower.requiredDraws.toStringAsExponential(2),
                  ),
                  StatTile(
                    label: 'years to detect it',
                    value: physicsPower.requiredYears.toStringAsExponential(2),
                    color: kDanger,
                    emphasis: true,
                  ),
                  StatTile(
                    label: 'power today',
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
          const Text(
            'No results yet.',
            style: TextStyle(color: kMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _RunBar(running: running, onRun: onRun),
        ],
      ),
    );
  }
}
