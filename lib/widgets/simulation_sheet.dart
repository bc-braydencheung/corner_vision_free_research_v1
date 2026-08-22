import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/simulation_draft.dart';

/// Stake entry for one pick, opened from `加入模擬戶口` on a card.
///
/// The market side of the sheet is read-only: the line, the price and both
/// probabilities are the ones the card published, so a recorded bet can always
/// be audited against the quote it was taken at. Only the stake is the user's.
class SimulationSheet extends StatefulWidget {
  const SimulationSheet({
    required this.draft,
    required this.balance,
    required this.available,
    required this.onConfirm,
    super.key,
  });

  final SimulationDraft draft;

  /// Account value the suggested stake is a fraction of.
  final double balance;

  /// Balance not already riding on an unsettled bet.
  final double available;

  /// Receives the stake once the user confirms it.
  final ValueChanged<double> onConfirm;

  @override
  State<SimulationSheet> createState() => _SimulationSheetState();
}

class _SimulationSheetState extends State<SimulationSheet> {
  late final TextEditingController _stake = TextEditingController(
    text: _suggested > 0 ? _suggested.toStringAsFixed(0) : '',
  );

  /// Quarter-Kelly stake of the pick, the same sizing the card prints.
  double get _suggested {
    final raw = widget.balance * widget.draft.stakeFraction;
    final capped = raw > widget.available ? widget.available : raw;
    return capped <= 0 ? 0 : (capped / 10).roundToDouble() * 10;
  }

  @override
  void dispose() {
    _stake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final stake = double.tryParse(_stake.text.trim());
    final tooLarge = stake != null && stake > widget.available;
    final valid = stake != null && stake > 0 && !tooLarge;
    final kickedOff = !draft.startTime.toUtc().isAfter(DateTime.now().toUtc());
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                draft.subject,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${draft.leagueName} · ${_time(draft.startTime)} 開賽 · 模擬研究記錄',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '賠率來源：'
                '${draft.marketSource.isEmpty ? '馬會' : draft.marketSource}'
                '${draft.marketCapturedAt == null ? '' : ' · 擷取於 ${_time(draft.marketCapturedAt!)}'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
              _SelectionPanel(draft: draft),
              const SizedBox(height: 14),
              _FigureGrid(draft: draft),
              const SizedBox(height: 18),
              Row(
                children: [
                  Text(
                    '虛擬注碼',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '可用 ${widget.available.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _stake,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '輸入注碼',
                  errorText: tooLarge ? '超出可用餘額' : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_suggested > 0)
                    _StakeChip(
                      label: '模型建議 ${_suggested.toStringAsFixed(0)}',
                      onTap: () => _set(_suggested),
                    ),
                  for (final amount in const [50.0, 100.0, 200.0, 500.0])
                    if (amount <= widget.available)
                      _StakeChip(
                        label: amount.toStringAsFixed(0),
                        onTap: () => _set(amount),
                      ),
                ],
              ),
              const SizedBox(height: 16),
              _ReturnRow(
                stake: stake ?? 0,
                odds: draft.odds,
                enabled: valid && !kickedOff,
              ),
              const SizedBox(height: 14),
              if (kickedOff)
                const _Note(
                  text: '此場已開賽，不再接受新的模擬記錄。',
                  colour: Color(0xFFFFC857),
                )
              else if (stake != null && _suggested > 0 && stake > _suggested)
                _Note(
                  text:
                      '注碼高於模型建議的 ${_suggested.toStringAsFixed(0)}（四分一 Kelly）。',
                  colour: const Color(0xFFFFC857),
                ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: valid && !kickedOff
                      ? () {
                          widget.onConfirm(stake);
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('確認加入模擬戶口'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '模擬戶口只記錄虛擬研究下注：App 不提供真實投注、付款或轉帳，'
                '盤口與賠率取自推介當時的馬會資料，不可修改。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _set(double amount) {
    _stake.text = amount.toStringAsFixed(0);
    setState(() {});
  }
}

/// The published selection and price, shown as a locked panel.
class _SelectionPanel extends StatelessWidget {
  const _SelectionPanel({required this.draft});

  final SimulationDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF123A2A), Color(0xFF0A1F16)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x3342E695)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '推介盤口（不可修改）',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  draft.selectionLabel,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF42E695),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '馬會賠率',
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                draft.odds.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Model and market figures of the pick, as published on the card.
class _FigureGrid extends StatelessWidget {
  const _FigureGrid({required this.draft});

  final SimulationDraft draft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: '模型機率',
                  value:
                      '${(draft.modelProbability * 100).toStringAsFixed(1)}%',
                  highlight: true,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: '市場公平機率',
                  value:
                      '${(draft.marketProbability * 100).toStringAsFixed(1)}%',
                ),
              ),
              Expanded(
                child: _Figure(
                  label: '公平賠率',
                  value: draft.fairOdds <= 0
                      ? '—'
                      : draft.fairOdds.toStringAsFixed(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: '模型期望值',
                  value: '${(draft.edge * 100).toStringAsFixed(1)}%',
                  highlight: true,
                ),
              ),
              Expanded(
                child: _Figure(label: '模型信心', value: draft.confidenceLabel),
              ),
              Expanded(
                child: _Figure(
                  label: draft.recommended ? '狀態' : '狀態（觀察）',
                  value: draft.recommended ? '模型推介' : '未達門檻',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StakeChip extends StatelessWidget {
  const _StakeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  const _ReturnRow({
    required this.stake,
    required this.odds,
    required this.enabled,
  });

  final double stake;
  final double odds;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final gross = stake * odds;
    return Row(
      children: [
        Expanded(
          child: _Figure(
            label: '中則可得',
            value: enabled ? gross.toStringAsFixed(2) : '—',
          ),
        ),
        Expanded(
          child: _Figure(
            label: '淨賺',
            value: enabled ? (gross - stake).toStringAsFixed(2) : '—',
            highlight: true,
          ),
        ),
        Expanded(
          child: _Figure(
            label: '最多輸',
            value: enabled ? stake.toStringAsFixed(2) : '—',
          ),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: highlight ? const Color(0xFF42E695) : Colors.white,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: colour, fontSize: 11.5, height: 1.4),
      ),
    );
  }
}

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
