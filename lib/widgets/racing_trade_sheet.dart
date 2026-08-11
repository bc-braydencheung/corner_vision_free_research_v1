import 'package:flutter/material.dart';

import '../models/forecast_data.dart';
import '../models/simulated_trade.dart';

class RacingTradeSheet extends StatefulWidget {
  const RacingTradeSheet({
    required this.race,
    required this.runner,
    required this.modelVersion,
    required this.availableBalance,
    required this.onBuy,
    this.maximumStake,
    super.key,
  });

  final RacingRace race;
  final RacingRunner runner;
  final String modelVersion;
  final double availableBalance;
  final ValueChanged<SimulatedTrade> onBuy;
  final double? maximumStake;

  @override
  State<RacingTradeSheet> createState() => _RacingTradeSheetState();
}

class _RacingTradeSheetState extends State<RacingTradeSheet> {
  final _oddsController = TextEditingController(text: '5.00');
  final _stakeController = TextEditingController(text: '2.5');
  String _marketType = 'win';
  String _stakeMode = 'fixed';

  @override
  void dispose() {
    _oddsController.dispose();
    _stakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final odds = double.tryParse(_oddsController.text);
    final stake = double.tryParse(_stakeController.text);
    final maximumStake = widget.maximumStake ?? widget.availableBalance * 0.005;
    final modelProbability = _marketType == 'win'
        ? widget.runner.winProbability
        : widget.runner.placeProbability;
    final fairOdds = _marketType == 'win'
        ? widget.runner.fairWinOdds
        : widget.runner.fairPlaceOdds;
    final valid =
        widget.race.startTime.toUtc().isAfter(DateTime.now().toUtc()) &&
        odds != null &&
        odds > 1 &&
        odds <= 1000 &&
        stake != null &&
        stake > 0 &&
        stake <= maximumStake;
    final ev = odds == null ? null : modelProbability * odds - 1;
    final margin = (1 - widget.runner.confidenceScore).clamp(0.0, 1.0) * 0.06;
    final conservativeProbability = (modelProbability - margin).clamp(0.0, 1.0);
    final minimumAcceptableOdds = conservativeProbability == 0
        ? null
        : 1.05 / conservativeProbability;
    final conservativeEv = odds == null
        ? null
        : conservativeProbability * odds - 1;
    final tenthKellyStake =
        odds == null ||
            odds <= 1 ||
            conservativeEv == null ||
            conservativeEv <= 0
        ? 0.0
        : (widget.availableBalance * conservativeEv / (odds - 1) * 0.1).clamp(
            0.0,
            maximumStake,
          );
    final fixedStake = (widget.availableBalance * 0.0025).clamp(
      0.0,
      maximumStake,
    );
    final canBuy =
        valid &&
        conservativeEv != null &&
        conservativeEv >= 0.05 &&
        widget.runner.recommendation != 'no-prediction';
    final disabledReason = _disabledReason(
      now: DateTime.now().toUtc(),
      odds: odds,
      stake: stake,
      maximumStake: maximumStake,
      conservativeEv: conservativeEv,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.runner.number}號 ${widget.runner.horseName}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${widget.race.venue}第${widget.race.raceNumber}場 · '
                '${_marketType == 'win' ? '獨贏' : '位置'} · 僅限虛擬模擬',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'win', label: Text('獨贏')),
                  ButtonSegment(value: 'place', label: Text('位置')),
                ],
                selected: {_marketType},
                onSelectionChanged: (selection) {
                  setState(() {
                    _marketType = selection.first;
                    _oddsController.text = _marketType == 'win'
                        ? '5.00'
                        : '2.00';
                  });
                },
              ),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'fixed', label: Text('固定0.25%')),
                  ButtonSegment(value: 'kelly', label: Text('十分一Kelly')),
                ],
                selected: {_stakeMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _stakeMode = selection.first;
                    _stakeController.text =
                        (_stakeMode == 'fixed' ? fixedStake : tenthKellyStake)
                            .toStringAsFixed(2);
                  });
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _oddsController,
                      label: '十進制賠率',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      controller: _stakeController,
                      label: '虛擬注碼',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '用戶輸入的賠率只用於個人模擬 · 可用 '
                '${widget.availableBalance.toStringAsFixed(1)} · '
                '單項風控上限0.5% · ${maximumStake.toStringAsFixed(1)} units',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _ValueRow(
                      label: '模型${_marketType == 'win' ? '獨贏' : '位置'}機率',
                      value: '${(modelProbability * 100).toStringAsFixed(1)}%',
                    ),
                    _ValueRow(
                      label: '模型公平賠率',
                      value: fairOdds.toStringAsFixed(2),
                    ),
                    _ValueRow(
                      label: '保守研究限價',
                      value: minimumAcceptableOdds?.toStringAsFixed(2) ?? '—',
                    ),
                    _ValueRow(
                      label: '模型 EV',
                      value: ev == null ? '—' : _percent(ev),
                    ),
                    _ValueRow(
                      label: '保守 EV',
                      value: conservativeEv == null
                          ? '—'
                          : _percent(conservativeEv),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                canBuy ? '保守 EV 至少+5%，可加入不可修改的模擬記錄。' : disabledReason,
                style: TextStyle(
                  color: canBuy
                      ? const Color(0xFF42E695)
                      : const Color(0xFFFFC857),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: !canBuy
                      ? null
                      : () {
                          final now = DateTime.now().toUtc();
                          widget.onBuy(
                            SimulatedTrade(
                              id:
                                  '${widget.race.raceId}-'
                                  '${widget.runner.horseId}-'
                                  '${now.microsecondsSinceEpoch}',
                              matchId: widget.race.raceId,
                              leagueCode: 'HK',
                              leagueName: '香港賽馬',
                              homeTeam: widget.runner.horseName,
                              awayTeam:
                                  '${widget.race.venue}第${widget.race.raceNumber}場',
                              matchDate: widget.race.date,
                              createdAt: now,
                              direction: 'win',
                              line: 0,
                              odds: odds,
                              stake: stake,
                              modelWinProbability: modelProbability,
                              modelPushProbability: 0,
                              expectedValue: ev!,
                              confidence: widget.runner.confidence,
                              status: 'open',
                              actualTotalCorners: null,
                              profit: null,
                              sport: 'racing',
                              marketType: _marketType,
                              selectionId: widget.runner.horseId,
                              placeSlots: widget.race.runners.length >= 7
                                  ? 3
                                  : widget.race.runners.length >= 4
                                  ? 2
                                  : 0,
                              modelVersion: widget.modelVersion,
                              stakeStrategy: _stakeMode,
                              marketSource: 'user-entered-price',
                              marketCapturedAt: now,
                              minimumAcceptableOdds: minimumAcceptableOdds,
                            ),
                          );
                          Navigator.pop(context);
                        },
                  child: Text('確認${_marketType == 'win' ? '獨贏' : '位置'}模擬買入'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _percent(double value) {
    final sign = value >= 0 ? '+' : '';
    return '$sign${(value * 100).toStringAsFixed(1)}%';
  }

  String _disabledReason({
    required DateTime now,
    required double? odds,
    required double? stake,
    required double maximumStake,
    required double? conservativeEv,
  }) {
    if (!widget.race.startTime.toUtc().isAfter(now)) {
      return '賽事已開跑或完成，不能建立新的模擬記錄。';
    }
    if (widget.runner.recommendation == 'no-prediction') {
      return '模型信心不足，這匹馬標記為「不預測」，不能建立模擬記錄。';
    }
    if (odds == null || odds <= 1 || odds > 1000) {
      return '請輸入大於 1.00、最高 1000.00 的有效十進制賠率。';
    }
    if (stake == null || stake <= 0) {
      return '請輸入大於 0 的虛擬注碼。';
    }
    if (stake > maximumStake) {
      return '虛擬注碼超過單項0.5%／每日2%剩餘上限 '
          '${maximumStake.toStringAsFixed(1)} units。';
    }
    if (conservativeEv == null || conservativeEv < 0.05) {
      return '按目前賠率計算的保守 EV 未達+5%安全邊際，不能建立模擬記錄。';
    }
    return '目前輸入未達模擬買入條件。';
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: onChanged,
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
          ),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
