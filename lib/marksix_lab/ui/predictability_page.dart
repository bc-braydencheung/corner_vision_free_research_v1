import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../physics/predictability.dart';
import 'theme.dart';
import 'widgets/charts.dart';
import 'widgets/panels.dart';

class PredictabilityPage extends StatefulWidget {
  const PredictabilityPage({super.key});

  @override
  State<PredictabilityPage> createState() => _PredictabilityPageState();
}

class _PredictabilityPageState extends State<PredictabilityPage> {
  PredictabilityParams _params = const PredictabilityParams();

  String _exp(double log10Value) {
    if (!log10Value.isFinite) return log10Value.isNegative ? '0' : 'inf';
    final e = log10Value.floor();
    final mantissa = math.pow(10, log10Value - e).toDouble();
    return '${mantissa.toStringAsFixed(2)}e$e';
  }

  @override
  Widget build(BuildContext context) {
    final r = computePredictability(_params);
    final decay = <Offset>[];
    for (var i = 0; i <= 120; i++) {
      final t = _params.stirTime * i / 120;
      decay.add(
        Offset(
          t,
          (math.log(r.initialInformationBits) - r.lyapunovExponent * t) /
              math.ln10,
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const InfoBanner(
          icon: Icons.functions,
          text:
              'Chaos does not make the draw hard to predict. It makes '
              'prediction impossible in the information-theoretic sense: the '
              'mutual information between any knowable initial state and the '
              'outcome decays as exp(-lambda t), and molecular - ultimately '
              'quantum - noise sets the floor. Every parameter below is exposed '
              'so the conclusion can be attacked instead of believed.',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Predictability bound',
          subtitle:
              'I(t) = log2 C(49,6) · exp(-lambda t),  '
              'lambda = nu · ln A',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: 'surviving information',
                    value: '${_exp(r.log10InformationBits)} bit',
                    hint:
                        'after ${_params.stirTime.toStringAsFixed(0)} s of mixing',
                    emphasis: true,
                    color: kDanger,
                  ),
                  StatTile(
                    label: 'lambda',
                    value: '${r.lyapunovExponent.toStringAsFixed(1)} /s',
                    hint:
                        'Lyapunov time ${(r.lyapunovTime * 1000).toStringAsFixed(1)} ms',
                  ),
                  StatTile(
                    label: 'bits erased per second',
                    value: r.bitsDestroyedPerSecond.toStringAsFixed(1),
                    hint: 'the draw only carries 23.74 bits in total',
                  ),
                  StatTile(
                    label: 'required precision',
                    value: '${_exp(r.log10RequiredPrecisionMetres)} m',
                    hint: r.belowPlanckScale
                        ? 'finer than the Planck length: physically meaningless'
                        : '${_exp(r.log10PrecisionOverPlanck)} Planck lengths',
                    color: r.belowPlanckScale ? kDanger : kAccentWarm,
                    emphasis: true,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LineChart(
                series: <Series>[
                  Series(
                    points: decay,
                    color: kAccent,
                    label: 'log10 surviving information (bits)',
                  ),
                ],
                xLabel: 'stirring time (s)',
                height: 220,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Noise floors',
          subtitle:
              'Even a perfect operator cannot set the initial state more '
              'precisely than the thermal motion of the air, and no one can beat '
              'the standard quantum limit.',
          child: StatWrap(
            children: <Widget>[
              StatTile(
                label: 'thermal floor',
                value: '${_exp(math.log(r.thermalFloor) / math.ln10)} m',
                hint: 'sqrt(kT/m) over one collision interval',
              ),
              StatTile(
                label: 'quantum floor',
                value: '${_exp(math.log(r.quantumFloor) / math.ln10)} m',
                hint: 'sqrt(hbar/(2 m nu))',
              ),
              StatTile(
                label: 'thermal -> macroscopic',
                value: '${r.macroTimeFromThermal.toStringAsFixed(2)} s',
                hint: 'time to reach chamber scale',
              ),
              StatTile(
                label: 'quantum -> macroscopic',
                value: '${r.macroTimeFromQuantum.toStringAsFixed(2)} s',
                hint: 'quantum uncertainty becomes visible this fast',
                emphasis: true,
              ),
              StatTile(
                label: 'engineering control',
                value: '${r.macroTimeFromControl.toStringAsFixed(2)} s',
                hint: 'best case with 0.1 mm placement control',
              ),
              StatTile(
                label: 'draw entropy',
                value: '${r.initialInformationBits.toStringAsFixed(2)} bit',
                hint: 'log2 C(49,6)',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Parameters',
          subtitle:
              'Order-of-magnitude defaults for a plausible machine. The '
              'model is not calibrated to any specific Mark Six apparatus: the '
              'machine type, ball material and loading procedure would all have '
              'to be confirmed from primary sources first.',
          child: Column(
            children: <Widget>[
              LabeledSlider(
                label: 'collision rate nu (per second)',
                value: _params.collisionRate,
                min: 5,
                max: 200,
                display: _params.collisionRate.toStringAsFixed(0),
                onChanged: (v) => setState(
                  () => _params = _params.copyWith(collisionRate: v),
                ),
              ),
              LabeledSlider(
                label: 'error amplification per collision A',
                value: _params.amplificationPerCollision,
                min: 1.05,
                max: 6,
                display: _params.amplificationPerCollision.toStringAsFixed(2),
                onChanged: (v) => setState(
                  () =>
                      _params = _params.copyWith(amplificationPerCollision: v),
                ),
              ),
              LabeledSlider(
                label: 'stirring time (s)',
                value: _params.stirTime,
                min: 1,
                max: 120,
                display: _params.stirTime.toStringAsFixed(0),
                onChanged: (v) =>
                    setState(() => _params = _params.copyWith(stirTime: v)),
              ),
              LabeledSlider(
                label: 'chamber scale L (m)',
                value: _params.chamberScale,
                min: 0.1,
                max: 1.0,
                display: _params.chamberScale.toStringAsFixed(2),
                onChanged: (v) =>
                    setState(() => _params = _params.copyWith(chamberScale: v)),
              ),
              LabeledSlider(
                label: 'ball mass (g)',
                value: _params.ballMass * 1000,
                min: 1,
                max: 100,
                display: (_params.ballMass * 1000).toStringAsFixed(1),
                onChanged: (v) => setState(
                  () => _params = _params.copyWith(ballMass: v / 1000),
                ),
              ),
              LabeledSlider(
                label: 'placement control dx0 (mm)',
                value: _params.controlUncertainty * 1000,
                min: 0.001,
                max: 5,
                display: (_params.controlUncertainty * 1000).toStringAsFixed(3),
                onChanged: (v) => setState(
                  () =>
                      _params = _params.copyWith(controlUncertainty: v / 1000),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
