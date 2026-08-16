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
              '混沌不是使開獎「難以預測」，而是在資訊理論意義上使預測不可能：'
              '任何可知初始狀態與結果之間的互資訊以 exp(-λt) 衰減，'
              '而分子熱噪聲（最終是量子噪聲）設下下限。下面所有參數都公開，'
              '讓你可以去挑戰結論，而不是相信結論。',
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '可預測上界',
          subtitle: 'I(t) = log2 C(49,6) · exp(-λt)，λ = ν · ln A',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              StatWrap(
                children: <Widget>[
                  StatTile(
                    label: '殘留資訊量',
                    value: '${_exp(r.log10InformationBits)} 位元',
                    hint: '攪拌 ${_params.stirTime.toStringAsFixed(0)} 秒之後',
                    emphasis: true,
                    color: kDanger,
                  ),
                  StatTile(
                    label: 'λ（Lyapunov 指數）',
                    value: '${r.lyapunovExponent.toStringAsFixed(1)} /s',
                    hint:
                        'Lyapunov 時間 ${(r.lyapunovTime * 1000).toStringAsFixed(1)} 毫秒',
                  ),
                  StatTile(
                    label: '每秒抹除位元',
                    value: r.bitsDestroyedPerSecond.toStringAsFixed(1),
                    hint: '一期開獎全部只有 23.74 位元',
                  ),
                  StatTile(
                    label: '所需初始精度',
                    value: '${_exp(r.log10RequiredPrecisionMetres)} 米',
                    hint: r.belowPlanckScale
                        ? '比普朗克長度更細：物理上沒有意義'
                        : '${_exp(r.log10PrecisionOverPlanck)} 個普朗克長度',
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
                    label: 'log10 殘留資訊量（位元）',
                  ),
                ],
                xLabel: '攪拌時間（秒）',
                height: 220,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '噪聲下限',
          subtitle: '即使操作完美，初始狀態也不可能比空氣熱運動更精確，而沒人能突破標準量子極限。',
          child: StatWrap(
            children: <Widget>[
              StatTile(
                label: '熱噪聲下限',
                value: '${_exp(math.log(r.thermalFloor) / math.ln10)} 米',
                hint: '在一次碰撞間隔內的 sqrt(kT/m)',
              ),
              StatTile(
                label: '量子下限',
                value: '${_exp(math.log(r.quantumFloor) / math.ln10)} 米',
                hint: 'sqrt(hbar/(2 m nu))',
              ),
              StatTile(
                label: '熱噪聲 → 宏觀',
                value: '${r.macroTimeFromThermal.toStringAsFixed(2)} 秒',
                hint: '放大到攪珠室尺度所需時間',
              ),
              StatTile(
                label: '量子 → 宏觀',
                value: '${r.macroTimeFromQuantum.toStringAsFixed(2)} 秒',
                hint: '量子不確定性這麼快就變成可見',
                emphasis: true,
              ),
              StatTile(
                label: '工程控制極限',
                value: '${r.macroTimeFromControl.toStringAsFixed(2)} 秒',
                hint: '以 0.1 毫米放置精度的最佳情況',
              ),
              StatTile(
                label: '開獎熵',
                value: '${r.initialInformationBits.toStringAsFixed(2)} 位元',
                hint: 'log2 C(49,6)',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '參數',
          subtitle:
              '預設值只是合理機型的量級估算，並未校準到任何特定六合彩攪珠機：'
              '機型、球體材質、裝球程序都需要先從一手資料證實。',
          child: Column(
            children: <Widget>[
              LabeledSlider(
                label: '碰撞頻率 ν（每秒）',
                value: _params.collisionRate,
                min: 5,
                max: 200,
                display: _params.collisionRate.toStringAsFixed(0),
                onChanged: (v) => setState(
                  () => _params = _params.copyWith(collisionRate: v),
                ),
              ),
              LabeledSlider(
                label: '每次碰撞誤差放大倍數 A',
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
                label: '攪拌時間（秒）',
                value: _params.stirTime,
                min: 1,
                max: 120,
                display: _params.stirTime.toStringAsFixed(0),
                onChanged: (v) =>
                    setState(() => _params = _params.copyWith(stirTime: v)),
              ),
              LabeledSlider(
                label: '攪珠室尺度 L（米）',
                value: _params.chamberScale,
                min: 0.1,
                max: 1.0,
                display: _params.chamberScale.toStringAsFixed(2),
                onChanged: (v) =>
                    setState(() => _params = _params.copyWith(chamberScale: v)),
              ),
              LabeledSlider(
                label: '球質量（克）',
                value: _params.ballMass * 1000,
                min: 1,
                max: 100,
                display: (_params.ballMass * 1000).toStringAsFixed(1),
                onChanged: (v) => setState(
                  () => _params = _params.copyWith(ballMass: v / 1000),
                ),
              ),
              LabeledSlider(
                label: '放置控制精度 Δx₀（毫米）',
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
