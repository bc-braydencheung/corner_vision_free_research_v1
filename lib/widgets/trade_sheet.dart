import 'package:flutter/material.dart';

import '../models/forecast_data.dart';
import '../models/simulated_trade.dart';

class TradeSheet extends StatefulWidget {
  const TradeSheet({
    required this.prediction,
    required this.availableBalance,
    required this.onBuy,
    this.maximumStake,
    super.key,
  });

  final MatchPrediction prediction;
  final double availableBalance;
  final ValueChanged<SimulatedTrade> onBuy;
  final double? maximumStake;

  @override
  State<TradeSheet> createState() => _TradeSheetState();
}

class _TradeSheetState extends State<TradeSheet> {
  final _lineController = TextEditingController(text: '9.5');
  final _oddsController = TextEditingController(text: '1.90');
  final _stakeController = TextEditingController(text: '2.5');
  String _direction = 'over';
  String _stakeMode = 'fixed';

  @override
  void initState() {
    super.initState();
    final prediction = widget.prediction;
    if (prediction.marketAvailable &&
        prediction.marketLine != null &&
        prediction.researchDirection.isNotEmpty) {
      _direction = prediction.researchDirection;
      _lineController.text = prediction.marketLine!.toStringAsFixed(2);
      final odds = _direction == 'over'
          ? prediction.marketOverOdds
          : prediction.marketUnderOdds;
      if (odds != null) {
        _oddsController.text = odds.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _lineController.dispose();
    _oddsController.dispose();
    _stakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = double.tryParse(_lineController.text);
    final odds = double.tryParse(_oddsController.text);
    final stake = double.tryParse(_stakeController.text);
    final maximumStake = widget.maximumStake ?? widget.availableBalance * 0.005;
    final validIncrement =
        line != null && ((line * 4) - (line * 4).round()).abs() < 0.0001;
    final valid =
        line != null &&
        line >= 0 &&
        line <= 25 &&
        validIncrement &&
        odds != null &&
        odds > 1 &&
        odds <= 100 &&
        stake != null &&
        stake > 0 &&
        stake <= maximumStake;
    final outcome = valid
        ? widget.prediction.probabilities(direction: _direction, line: line)
        : null;
    final ev = valid
        ? widget.prediction.expectedValue(
            direction: _direction,
            line: line,
            odds: odds,
          )
        : null;
    final uncertaintyMargin =
        (1 - widget.prediction.confidenceScore).clamp(0.0, 1.0) * 0.08;
    final conservativeWin =
        widget.prediction.marketAvailable &&
            widget.prediction.conservativeProbability != null
        ? widget.prediction.conservativeProbability
        : outcome == null
        ? null
        : (outcome.win - uncertaintyMargin).clamp(0.0, 1.0);
    final conservativeLoss = outcome == null || conservativeWin == null
        ? null
        : (1 - outcome.push - conservativeWin).clamp(0.0, 1.0);
    final conservativeEv =
        conservativeWin == null || conservativeLoss == null || odds == null
        ? null
        : conservativeWin * (odds - 1) - conservativeLoss;
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
        widget.prediction.tradeEligible &&
        widget.prediction.recommendation != 'no-prediction';

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
                '${widget.prediction.homeTeam} 對 ${widget.prediction.awayTeam}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${widget.prediction.leagueName} · 僅限虛擬模擬',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'over', label: Text('大')),
                  ButtonSegment(value: 'under', label: Text('小')),
                ],
                selected: {_direction},
                onSelectionChanged: widget.prediction.marketAvailable
                    ? null
                    : (selection) {
                        setState(() => _direction = selection.first);
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
                      controller: _lineController,
                      label: '角球盤',
                      enabled: !widget.prediction.marketAvailable,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _NumberField(
                      controller: _oddsController,
                      label: '十進制賠率',
                      enabled: !widget.prediction.marketAvailable,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
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
                '只接受0.25角球刻度 · 可用 ${widget.availableBalance.toStringAsFixed(1)} · '
                '單項風控上限0.5% · ${maximumStake.toStringAsFixed(1)} units',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 10,
                ),
              ),
              if (widget.prediction.marketAvailable)
                Text(
                  '${widget.prediction.marketSource} · '
                  '${widget.prediction.marketCapturedAt?.toUtc().toIso8601String() ?? ''} · '
                  '研究限價 ${widget.prediction.minimumAcceptableOdds?.toStringAsFixed(2) ?? '—'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _ValueRow(
                      label: '勝出／半贏機率',
                      value: outcome == null
                          ? '—'
                          : '${(outcome.win * 100).toStringAsFixed(1)}%',
                    ),
                    _ValueRow(
                      label: '退回／半退機率',
                      value: outcome == null
                          ? '—'
                          : '${(outcome.push * 100).toStringAsFixed(1)}%',
                    ),
                    _ValueRow(
                      label: '模型 EV',
                      value: ev == null ? '—' : _percent(ev),
                      color: ev != null && ev > 0
                          ? const Color(0xFF42E695)
                          : const Color(0xFFFF8FA3),
                    ),
                    _ValueRow(
                      label: '保守 EV',
                      value: conservativeEv == null
                          ? '—'
                          : _percent(conservativeEv),
                      color: conservativeEv != null && conservativeEv > 0
                          ? const Color(0xFF42E695)
                          : const Color(0xFFFF8FA3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                canBuy
                    ? '保守EV至少+5%，可加入不可修改的模擬記錄。'
                    : '保守EV、安全邊際或模型閘門未達門檻，不會建立模擬買入。',
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
                              id: '${widget.prediction.matchId}-${now.microsecondsSinceEpoch}',
                              matchId: widget.prediction.matchId,
                              leagueCode: widget.prediction.leagueCode,
                              leagueName: widget.prediction.leagueName,
                              homeTeam: widget.prediction.homeTeam,
                              awayTeam: widget.prediction.awayTeam,
                              matchDate: widget.prediction.date,
                              createdAt: now,
                              direction: _direction,
                              line: line,
                              odds: odds,
                              stake: stake,
                              modelWinProbability: outcome!.win,
                              modelPushProbability: outcome.push,
                              expectedValue: ev!,
                              confidence: widget.prediction.confidence,
                              status: 'open',
                              actualTotalCorners: null,
                              profit: null,
                              stakeStrategy: _stakeMode,
                              marketSource: widget.prediction.marketSource,
                              marketCapturedAt:
                                  widget.prediction.marketCapturedAt,
                              minimumAcceptableOdds:
                                  widget.prediction.minimumAcceptableOdds,
                            ),
                          );
                          Navigator.pop(context);
                        },
                  child: const Text('確認模擬買入'),
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
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
      enabled: enabled,
      onChanged: onChanged,
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

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
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
