import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/simulated_trade.dart';
import 'share_canvas.dart';
import 'simulation_ledger.dart';
import 'simulation_share_image.dart';

/// Hands a simulated bet, or the whole ledger, to WhatsApp as a card image.
///
/// The image carries the figures; the text body repeats what a target that
/// cannot take a picture still needs, the simulation disclosure included.
class SimulationShareService {
  const SimulationShareService();

  Future<void> shareTrade({
    required SimulatedTrade trade,
    required DateTime asOf,
  }) async {
    final image = await renderSimulationTradeShareImage(
      trade: trade,
      asOf: asOf,
    );
    await _send(
      image: image,
      name: 'edgewise-sim-bet-${_stamp(asOf)}.png',
      text: buildSimulationTradeShareText(trade: trade, asOf: asOf),
      subject: '睿測 · 模擬戶口下注',
    );
  }

  Future<void> shareLedger({
    required List<SimulatedTrade> trades,
    required SimulationLedger ledger,
    required DateTime asOf,
  }) async {
    final image = await renderSimulationLedgerShareImage(
      trades: trades,
      ledger: ledger,
      asOf: asOf,
    );
    await _send(
      image: image,
      name: 'edgewise-sim-ledger-${_stamp(asOf)}.png',
      text: buildSimulationLedgerShareText(
        trades: trades,
        ledger: ledger,
        asOf: asOf,
      ),
      subject: '睿測 · 模擬戶口買賣記錄',
    );
  }

  Future<void> _send({
    required ShareCardImage image,
    required String name,
    required String text,
    required String subject,
  }) async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/share',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(image.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: text,
        subject: subject,
      ),
    );
  }

  static String _stamp(DateTime asOf) {
    final local = asOf.toLocal();
    return '${local.year}${_two(local.month)}${_two(local.day)}'
        '-${_two(local.hour)}${_two(local.minute)}${_two(local.second)}';
  }
}

/// Text version of one simulated bet.
String buildSimulationTradeShareText({
  required SimulatedTrade trade,
  required DateTime asOf,
}) {
  final lines = <String>[
    '睿測 · 模擬戶口下注（${shareStamp(asOf)}）',
    '${trade.leagueName} · ${trade.subject}',
    '${trade.selectionText} @ ${trade.odds.toStringAsFixed(2)}',
    '注碼 ${trade.stake.toStringAsFixed(2)} · '
        '中則可得 ${(trade.stake * trade.odds).toStringAsFixed(2)}',
    '模型機率 ${(trade.modelWinProbability * 100).toStringAsFixed(1)}% · '
        '期望值 ${(trade.expectedValue * 100).toStringAsFixed(1)}%',
    trade.status == 'settled'
        ? '賽果 ${trade.actualTotalCorners == null ? '已結算' : '${trade.actualTotalCorners} 個角球'} · '
              '盈虧 ${_signed(trade.profit ?? 0)}'
        : '狀態：待賽果自動結算（${shareTime(trade.matchDate)} 開賽）',
    '模擬戶口只記錄虛擬研究下注，不涉及真實資金或投注。',
  ];
  return lines.join('\n');
}

/// Text version of the ledger summary.
String buildSimulationLedgerShareText({
  required List<SimulatedTrade> trades,
  required SimulationLedger ledger,
  required DateTime asOf,
}) {
  final lines = <String>[
    '睿測 · 模擬戶口買賣記錄（${shareStamp(asOf)}）',
    '戶口價值 ${ledger.balance.toStringAsFixed(2)} · '
        '可用 ${ledger.available.toStringAsFixed(2)}',
    '累計盈虧 ${_signed(ledger.profit)} · '
        '${ledger.hasSettled ? 'ROI ${(ledger.roi * 100).toStringAsFixed(2)}%' : 'ROI：未有已結算賽果'}',
    ledger.wins + ledger.losses == 0
        ? '命中率：未有已結算賽果'
        : '命中率 ${(ledger.hitRate * 100).toStringAsFixed(1)}%'
              '（${ledger.wins}／${ledger.wins + ledger.losses}）',
    '共 ${trades.length} 注 · 未結算 ${ledger.openCount} 注',
  ];
  for (final trade in simulationShareListing(trades)) {
    lines.add(
      '· ${trade.leagueName} ${trade.subject}｜'
      '${trade.selectionText} @${trade.odds.toStringAsFixed(2)}｜'
      '注 ${trade.stake.toStringAsFixed(2)}｜'
      '${trade.status == 'settled' ? _signed(trade.profit ?? 0) : '待結算'}',
    );
  }
  if (trades.length > simulationShareEntries) {
    lines.add('（只列最近 $simulationShareEntries 注）');
  }
  lines.add('模擬戶口只記錄虛擬研究下注，不涉及真實資金或投注。');
  return lines.join('\n');
}

String _signed(double value) =>
    '${value >= 0 ? '+' : '-'}${value.abs().toStringAsFixed(2)}';

String _two(int value) => value.toString().padLeft(2, '0');
