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
      if (_sim.time > 12) {
        _running = false;
        _ticker?.stop();
      }
      setState(() {});
    });
  }

  void _toggleRunning() {
    setState(() {
      _running = !_running;
      if (_running) {
        _ticker?.start();
      } else {
        _ticker?.stop();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _reset({double? perturbation, double? shakeFrequency}) {
    _ticker?.stop();
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
              '這是真實的數值實驗，不是動畫：49 顆非彈性圓盤在震動底面上運動，'
              '從相差一個奈米的兩組初始狀態各自積分。分離速度直接量到 λ；'
              '第二條曲線量的是另一回事——攪珠機多快忘記它裝球時的排序。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '孿生軌跡',
          subtitle:
              '兩份副本遵循完全相同的確定性動力學，只有其中一顆球的初始位置相差 '
              '${_sim.perturbation.toStringAsExponential(0)} 米。',
          trailing: Row(
            children: <Widget>[
              IconButton(
                onPressed: _toggleRunning,
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
                    label: '模擬時間',
                    value: '${_sim.time.toStringAsFixed(2)} 秒',
                  ),
                  StatTile(
                    label: '實測 λ',
                    value: lambda.isFinite
                        ? '${lambda.toStringAsFixed(1)} /s'
                        : '要跑久一點',
                    emphasis: true,
                  ),
                  StatTile(
                    label: '忘記裝球排序',
                    value: mixing.isFinite
                        ? '${mixing.toStringAsFixed(2)} 秒'
                        : '尚未',
                    hint: 'Kendall τ 距離達到 0.5',
                  ),
                  StatTile(
                    label: '置換混合時間',
                    value: spectralMixing.isFinite
                        ? '${spectralMixing.toStringAsFixed(2)} 秒'
                        : '-',
                    hint: '由譜隙推得的 Bayer-Diaconis 上界',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '分離度增長',
          subtitle:
              '在這個對數坐標上成直線，就是混沌的特徵。平台代表飽和：'
              '兩份副本已經像兩個毫無關係的系統，初始條件的資訊完全消失。',
          child: LineChart(
            series: <Series>[
              Series(
                points: divergence,
                color: kAccentWarm,
                label: 'log10 |x - x\'|（米）',
              ),
            ],
            xLabel: '時間（秒）',
            height: 210,
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '裝球排序的消失',
          subtitle:
              '混沌與混合是兩回事：混沌殺死預測，但只有混合才保證均勻。'
              '如果攪拌時間短於混合時間，攪珠機就可能殘留與裝球位置相關的偏差——'
              '這正是「機器審計」頁在真實資料上搜尋的東西。',
          child: LineChart(
            series: <Series>[
              Series(points: kendall, color: kAccent, label: 'Kendall τ 距離'),
              Series(
                points: <Offset>[
                  Offset(0, 0.5),
                  Offset(math.max(_sim.time, 0.1), 0.5),
                ],
                color: kMuted,
                label: '完全混合（0.5）',
                dashed: true,
              ),
            ],
            xLabel: '時間（秒）',
            yMin: 0,
            yMax: 1,
            height: 210,
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '實驗控制',
          child: Column(
            children: <Widget>[
              LabeledSlider(
                label: '初始扳動（log10 米）',
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
                label: '震動頻率（赫茲）',
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
