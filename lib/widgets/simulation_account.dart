import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/simulated_trade.dart';
import '../services/simulation_ledger.dart';

/// The simulated account: every virtual bet, its settlement and the ledger.
///
/// No real money, betting or transfer is involved anywhere on this page; the
/// figures are the arithmetic of the recorded stakes against the corner counts
/// and finishing positions the app already collects.
class SimulationAccount extends StatelessWidget {
  const SimulationAccount({
    required this.trades,
    required this.bankroll,
    required this.onShareTrade,
    required this.onShareAll,
    required this.onExport,
    required this.onImport,
    required this.onClear,
    required this.onBankrollChanged,
    this.busy = false,
    super.key,
  });

  final List<SimulatedTrade> trades;

  /// Starting balance the account is measured from.
  final double bankroll;
  final ValueChanged<SimulatedTrade> onShareTrade;
  final VoidCallback onShareAll;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onClear;
  final ValueChanged<double> onBankrollChanged;

  /// Set while a share, export or import is running, so it cannot double-fire.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ledger = buildSimulationLedger(trades: trades, bankroll: bankroll);
    final ordered = sortSimulationTrades(trades);
    final open = ordered.where((trade) => trade.status != 'settled').toList();
    final settled = ordered
        .where((trade) => trade.status == 'settled')
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '模擬戶口',
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '虛擬研究記錄 · 不涉及真實資金',
                    style: TextStyle(color: Color(0x8CFFFFFF), fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '設定本金',
              onPressed: () => _editBankroll(context),
              icon: const Icon(Icons.tune, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _BalanceCard(ledger: ledger),
        const SizedBox(height: 12),
        _Actions(
          busy: busy,
          hasTrades: trades.isNotEmpty,
          onShareAll: onShareAll,
          onExport: onExport,
          onImport: onImport,
          onClear: () => _confirmClear(context),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            '本頁為模擬研究記錄：App 不提供真實投注、付款或轉帳。'
            '每注的盤口與賠率取自加入時的馬會資料，賽果公布後自動結算盈虧。',
            style: TextStyle(fontSize: 11, height: 1.5),
          ),
        ),
        const SizedBox(height: 20),
        if (trades.isEmpty)
          const _EmptyAccount()
        else ...[
          if (open.isNotEmpty) ...[
            _SectionTitle(
              label: '未結算',
              detail: '${open.length} 注 · ${_money(ledger.openStake)}',
            ),
            for (final trade in open) ...[
              _TradeCard(trade: trade, onShare: () => onShareTrade(trade)),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
          if (settled.isNotEmpty) ...[
            _SectionTitle(
              label: '已結算',
              detail: '${settled.length} 注 · ${_signed(ledger.profit)}',
            ),
            for (final trade in settled) ...[
              _TradeCard(trade: trade, onShare: () => onShareTrade(trade)),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ],
    );
  }

  Future<void> _editBankroll(BuildContext context) async {
    final controller = TextEditingController(text: bankroll.toStringAsFixed(0));
    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('模擬本金'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '設定模擬戶口的起始金額（虛擬）。已記錄的下注不會改變，'
              '只影響戶口價值與可用餘額的基準。',
              style: TextStyle(fontSize: 12, height: 1.45),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              Navigator.of(
                context,
              ).pop(parsed != null && parsed > 0 ? parsed : null);
            },
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) {
      onBankrollChanged(value);
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除所有模擬記錄？'),
        content: Text(
          '將刪除全部 ${trades.length} 筆模擬下注記錄，不可復原。'
          '建議先「匯出 JSON」保留備份。研究紀錄、賠率快照等其他資料不受影響。',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3384C),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除全部'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      onClear();
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.ledger});

  final SimulationLedger ledger;

  @override
  Widget build(BuildContext context) {
    final up = ledger.profit >= 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12402E), Color(0xFF082016)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x2242E695)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '戶口價值（虛擬）',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(ledger.balance),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${_signed(ledger.profit)}'
                  '${ledger.hasSettled ? ' · ${_percent(ledger.roi)}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: up
                        ? const Color(0xFF42E695)
                        : const Color(0xFFFF8FA3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Metric(label: '本金', value: _money(ledger.bankroll)),
              _Metric(label: '可用餘額', value: _money(ledger.available)),
              _Metric(label: '未結算', value: '${ledger.openCount} 注'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Metric(
                label: '命中率',
                value: ledger.wins + ledger.losses == 0
                    ? '—'
                    : '${(ledger.hitRate * 100).toStringAsFixed(1)}%',
              ),
              _Metric(label: '已結算', value: '${ledger.settledCount} 注'),
              _Metric(
                label: '最大回撤',
                value: ledger.hasSettled
                    ? '${(ledger.maximumDrawdown * 100).toStringAsFixed(1)}%'
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.busy,
    required this.hasTrades,
    required this.onShareAll,
    required this.onExport,
    required this.onImport,
    required this.onClear,
  });

  final bool busy;
  final bool hasTrades;
  final VoidCallback onShareAll;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        FilledButton.icon(
          onPressed: busy || !hasTrades ? null : onShareAll,
          icon: const Icon(Icons.ios_share, size: 17),
          label: const Text('分享全部記錄'),
        ),
        OutlinedButton.icon(
          onPressed: busy || !hasTrades ? null : onExport,
          icon: const Icon(Icons.file_download_outlined, size: 17),
          label: const Text('匯出 JSON'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onImport,
          icon: const Icon(Icons.file_upload_outlined, size: 17),
          label: const Text('匯入檔案'),
        ),
        OutlinedButton.icon(
          onPressed: busy || !hasTrades ? null : onClear,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFFF8FA3),
            side: const BorderSide(color: Color(0x55FF8FA3)),
          ),
          icon: const Icon(Icons.delete_outline, size: 17),
          label: const Text('刪除全部'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.label, required this.detail});

  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF42E695),
            ),
          ),
          const Spacer(),
          Text(
            detail,
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeCard extends StatelessWidget {
  const _TradeCard({required this.trade, required this.onShare});

  final SimulatedTrade trade;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final profit = trade.profit;
    final pending = trade.status != 'settled' || profit == null;
    final colour = pending
        ? const Color(0xFFFFC857)
        : profit >= 0
        ? const Color(0xFF42E695)
        : const Color(0xFFFF8FA3);
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 13, 9, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF0E241B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${trade.leagueName} · ${_time(trade.matchDate)}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trade.subject,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    pending ? '待結算' : _signed(profit),
                    style: TextStyle(
                      color: colour,
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                  Text(
                    pending
                        ? '中則可得 ${_money(trade.stake * trade.odds)}'
                        : '注 ${_money(trade.stake)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: '分享此注',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _Tag(text: trade.selectionText, highlight: true),
              _Tag(text: '@ ${trade.odds.toStringAsFixed(2)}'),
              _Tag(text: '注 ${_money(trade.stake)}'),
              _Tag(
                text:
                    '模型 '
                    '${(trade.modelWinProbability * 100).toStringAsFixed(1)}%',
              ),
              _Tag(
                text: 'EV ${(trade.expectedValue * 100).toStringAsFixed(1)}%',
              ),
              if (trade.actualTotalCorners != null)
                _Tag(text: '實際 ${trade.actualTotalCorners} 角球'),
              if (trade.finishPosition != null)
                _Tag(text: '名次 ${trade.finishPosition}'),
              if (!trade.recommended) _Tag(text: '觀察記錄'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0x2242E695)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
          color: highlight
              ? const Color(0xFF42E695)
              : Colors.white.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _EmptyAccount extends StatelessWidget {
  const _EmptyAccount();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 42),
          SizedBox(height: 10),
          Text('尚未有模擬下注', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text(
            '在分析頁的推介卡片按「加入模擬戶口」，輸入虛擬注碼即可記錄；'
            '賽果公布後會自動計算盈虧。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

String _money(double value) => value.toStringAsFixed(2);

String _signed(double value) =>
    '${value >= 0 ? '+' : '-'}${value.abs().toStringAsFixed(2)}';

String _percent(double value) =>
    '${value >= 0 ? '+' : ''}${(value * 100).toStringAsFixed(1)}%';

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.month}/${local.day} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
