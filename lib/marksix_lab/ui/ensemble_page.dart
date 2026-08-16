import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../physics/hard_disk_ensemble.dart';
import '../stats/mixing_tests.dart';
import 'theme.dart';
import 'widgets/charts.dart';
import 'widgets/panels.dart';

class EnsemblePage extends StatefulWidget {
  const EnsemblePage({super.key});

  @override
  State<EnsemblePage> createState() => _EnsemblePageState();
}

class _EnsemblePageState extends State<EnsemblePage>
    with SingleTickerProviderStateMixin {
  HardDiskEnsemble _sim = HardDiskEnsemble();
  Ticker? _ticker;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (!_running) return;
      _sim.step(20);
      if (_sim.time > 12) _running = false;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _reset({double? perturbation, double? shakeFrequency}) {
    setState(() {
      _running = false;
      _sim = HardDiskEnsemble(
        perturbation: perturbation ?? _sim.perturbation,
        shakeFrequency: shakeFrequency ?? _sim.shakeFrequency,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final lambda = _sim.estimateLyapunov();
    final mixing = _sim.mixingTime();
    final divergence = <Offset>[
      for (var i = 0; i < _sim.times.length; i++)
        Offset(_sim.times[i], _sim.logSeparation[i] / math.ln10),
    ];
    final kendall = <Offset>[
      for (var i = 0; i < _sim.times.length; i++)
        Offset(_sim.times[i], _sim.kendallDistance[i]),
    ];

    final spectralMixing = lambda.isFinite && lambda > 0
        ? MixingTests.mixingTimeFromSpectralGap(
            secondEigenvalue: math.exp(-lambda * 0.05).clamp(1e-9, 0.999999),
          )
        : double.nan;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.scatter_plot,
          text:
              'A real numerical experiment, not an animation: 49 inelastic '
              'disks on a vibrating floor, integrated twice from initial states '
              'differing by one nanometre. The separation growth rate measures '
              'lambda directly. The second curve measures something different - '
              'how fast the machine forgets the ordered arrangement it was '
              'loaded in.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Twin trajectories',
          subtitle:
              'Both copies obey identical deterministic dynamics. Only the '
              'initial position of one disk differs, by '
              '${_sim.perturbation.toStringAsExponential(0)} m.',
          trailing: Row(
            children: <Widget>[
              IconButton(
                onPressed: () => setState(() => _running = !_running),
                icon: Icon(_running ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AspectRatio(
                aspectRatio: 1.3,
                child: CustomPaint(painter: _MixerPainter(_sim)),
              ),
              const SizedBox(height: 16),
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: 'simulated time',
                    value: '${_sim.time.toStringAsFixed(2)} s',
                  ),
                  StatTile(
                    label: 'measured lambda',
                    value: lambda.isFinite
                        ? '${lambda.toStringAsFixed(1)} /s'
                        : 'run longer',
                    emphasis: true,
                  ),
                  StatTile(
                    label: 'loading order forgotten',
                    value: mixing.isFinite
                        ? '${mixing.toStringAsFixed(2)} s'
                        : 'not yet',
                    hint: 'Kendall tau distance reaches 0.5',
                  ),
                  StatTile(
                    label: 'permutation mixing time',
                    value: spectralMixing.isFinite
                        ? '${spectralMixing.toStringAsFixed(2)} s'
                        : '-',
                    hint: 'Bayer-Diaconis bound from the spectral gap',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Separation growth',
          subtitle:
              'A straight line on this log axis is the signature of chaos. '
              'The plateau is saturation: the two copies are then as different as '
              'two unrelated systems, and all initial-condition information is '
              'gone.',
          child: LineChart(
            series: <Series>[
              Series(
                points: divergence,
                color: kAccentWarm,
                label: 'log10 |x - x\'| (m)',
              ),
            ],
            xLabel: 'time (s)',
            height: 210,
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Loss of the loading order',
          subtitle:
              'Chaos and mixing are different properties. Chaos kills '
              'prediction; only mixing guarantees uniformity. A machine stirred '
              'for less than its mixing time could retain a bias tied to loading '
              'position - which is what the mixing tests on the audit screen look '
              'for in real data.',
          child: LineChart(
            series: <Series>[
              Series(
                points: kendall,
                color: kAccent,
                label: 'Kendall tau distance',
              ),
              Series(
                points: <Offset>[
                  Offset(0, 0.5),
                  Offset(math.max(_sim.time, 0.1), 0.5),
                ],
                color: kMuted,
                label: 'fully mixed (0.5)',
                dashed: true,
              ),
            ],
            xLabel: 'time (s)',
            yMin: 0,
            yMax: 1,
            height: 210,
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Experiment controls',
          child: Column(
            children: <Widget>[
              LabeledSlider(
                label: 'initial perturbation (log10 m)',
                value: math.log(_sim.perturbation) / math.ln10,
                min: -12,
                max: -3,
                divisions: 9,
                display:
                    '1e${(math.log(_sim.perturbation) / math.ln10).round()}',
                onChanged: (v) =>
                    _reset(perturbation: math.pow(10, v.round()).toDouble()),
              ),
              LabeledSlider(
                label: 'shake frequency (Hz)',
                value: _sim.shakeFrequency,
                min: 2,
                max: 30,
                display: _sim.shakeFrequency.toStringAsFixed(0),
                onChanged: (v) => _reset(shakeFrequency: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _MixerPainter extends CustomPainter {
  _MixerPainter(this.sim);

  final HardDiskEnsemble sim;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / sim.width, size.height / sim.height);
    final originX = (size.width - sim.width * scale) / 2;
    final originY = (size.height - sim.height * scale) / 2;

    canvas.drawRect(
      Rect.fromLTWH(originX, originY, sim.width * scale, sim.height * scale),
      Paint()..color = kSurfaceAlt,
    );

    for (var i = 0; i < sim.count; i++) {
      final cx = originX + sim.x[i] * scale;
      final cy = originY + (sim.height - sim.y[i]) * scale;
      final hue = (i / sim.count) * 300;
      canvas.drawCircle(
        Offset(cx, cy),
        sim.radius * scale,
        Paint()..color = HSVColor.fromAHSV(1, hue, 0.55, 0.95).toColor(),
      );
      if (sim.radius * scale > 9) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              color: Colors.black.withValues(alpha: 0.75),
              fontSize: sim.radius * scale * 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MixerPainter old) => true;
}
