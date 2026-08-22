import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/simulated_trade.dart';
import 'share_canvas.dart';
import 'simulation_ledger.dart';

const _headerHeight = 236.0;
const _footerHeight = 176.0;
const _rowHeight = 48.0;
const _blockGap = 32.0;
const _entryHeight = 124.0;
const _badgeHeight = 96.0;

/// Positive figures keep the house green; a loss is drawn in a warm red so the
/// outcome of a card is readable without parsing the sign.
const _lossColour = ui.Color(0xFFFF6B6B);
const _pendingColour = ui.Color(0xFFFFC857);

/// How many of the newest rows the ledger card lists.
const simulationShareEntries = 8;

/// The newest rows a shared ledger card lists, unsettled ones first.
List<SimulatedTrade> simulationShareListing(List<SimulatedTrade> trades) =>
    sortSimulationTrades(trades).take(simulationShareEntries).toList();

/// Vertical layout of a single-bet card, in layout units.
///
/// The badge box and the figure rows are stacked, so a card is only correct
/// when [rowsTop] clears [badgeBottom]: the stake row used to be drawn inside
/// the selection badge and printed on top of it.
class SimulationTradeCardLayout {
  const SimulationTradeCardLayout({
    required this.badgeTop,
    required this.rowsTop,
    required this.rows,
    required this.height,
  });

  final double badgeTop;
  final double rowsTop;
  final int rows;
  final double height;

  double get badgeBottom => badgeTop + _badgeHeight;
  double get rowsBottom => rowsTop + rows * _rowHeight;
}

/// Where a single-bet card puts its badge and figure rows.
SimulationTradeCardLayout simulationTradeCardLayout(SimulatedTrade trade) {
  final rows = _tradeRows(trade).length;
  final badgeTop = _headerHeight + 112;
  final rowsTop = badgeTop + _badgeHeight + _blockGap;
  return SimulationTradeCardLayout(
    badgeTop: badgeTop,
    rowsTop: rowsTop,
    rows: rows,
    height: rowsTop + rows * _rowHeight + 44 + _footerHeight,
  );
}

/// Renders one simulated bet as a PNG at [shareCardScale] resolution.
///
/// Every number is taken from the stored row, so a shared card shows the price
/// and probability the bet was recorded at rather than today's quote. An
/// unsettled row prints `待結算` instead of a projected profit.
Future<ShareCardImage> renderSimulationTradeShareImage({
  required SimulatedTrade trade,
  required DateTime asOf,
}) async {
  final rows = _tradeRows(trade);
  final layout = simulationTradeCardLayout(trade);
  final height = layout.height;
  final recorder = ui.PictureRecorder();
  final canvas = beginShareCard(recorder, height);

  _paintHeader(canvas, '模擬戶口 · 單注記錄', asOf);

  var top = _headerHeight;
  paintShareText(
    canvas,
    trade.subject,
    ui.Offset(shareCardMargin, top),
    size: 44,
    weight: FontWeight.w900,
  );
  top += 60;
  paintShareText(
    canvas,
    '${trade.leagueName} · ${shareTime(trade.matchDate)} 開賽',
    ui.Offset(shareCardMargin, top),
    size: 26,
    color: shareCardMuted,
  );
  _paintBadge(canvas, trade, layout.badgeTop);

  // Rows start below the badge box, not inside it.
  var rowTop = layout.rowsTop;
  for (final row in rows) {
    _paintRow(canvas, row, rowTop);
    rowTop += _rowHeight;
  }

  _paintFooter(canvas, height);
  return endShareCard(recorder, height);
}

/// Renders the whole simulated ledger as a PNG at [shareCardScale] resolution.
///
/// The card is sized from the rows it draws, so the listing never runs past the
/// canvas however many bets the account holds; only the newest
/// [simulationShareEntries] are drawn and the count of the rest is stated.
Future<ShareCardImage> renderSimulationLedgerShareImage({
  required List<SimulatedTrade> trades,
  required SimulationLedger ledger,
  required DateTime asOf,
}) async {
  final listed = simulationShareListing(trades);
  final summary = _summaryRows(ledger);
  final height =
      _headerHeight +
      44 +
      summary.length * _rowHeight +
      _blockGap +
      (listed.isEmpty ? 78.0 : 48.0 + listed.length * _entryHeight + 46.0) +
      _footerHeight;
  final recorder = ui.PictureRecorder();
  final canvas = beginShareCard(recorder, height);

  _paintHeader(canvas, '模擬戶口 · 買賣記錄', asOf);

  var top = _headerHeight;
  paintShareText(
    canvas,
    '戶口摘要',
    ui.Offset(shareCardMargin, top),
    size: 26,
    color: shareCardGreen,
    weight: FontWeight.w700,
  );
  top += 44;
  for (final row in summary) {
    _paintRow(canvas, row, top);
    top += _rowHeight;
  }
  top += _blockGap;

  if (listed.isEmpty) {
    paintShareText(
      canvas,
      '尚未有任何模擬下注',
      ui.Offset(shareCardMargin, top),
      size: 32,
      weight: FontWeight.w800,
    );
  } else {
    paintShareText(
      canvas,
      '最近 ${listed.length} 注'
      '${trades.length > listed.length ? '（共 ${trades.length} 注）' : ''}',
      ui.Offset(shareCardMargin, top),
      size: 26,
      color: shareCardGreen,
      weight: FontWeight.w700,
    );
    top += 48;
    for (final trade in listed) {
      _paintEntry(canvas, trade, top);
      top += _entryHeight;
    }
  }

  _paintFooter(canvas, height);
  return endShareCard(recorder, height);
}

void _paintHeader(ui.Canvas canvas, String subtitle, DateTime asOf) {
  paintShareText(
    canvas,
    '睿測',
    const ui.Offset(shareCardMargin, 62),
    size: 62,
    weight: FontWeight.w900,
  );
  paintShareText(
    canvas,
    subtitle,
    const ui.Offset(shareCardMargin, 142),
    size: 30,
    color: shareCardGreen,
    weight: FontWeight.w700,
  );
  paintShareText(
    canvas,
    shareStamp(asOf),
    const ui.Offset(shareCardMargin, 184),
    size: 26,
    color: shareCardMuted,
  );
  paintShareRule(canvas, _headerHeight - 24);
}

void _paintFooter(ui.Canvas canvas, double height) {
  paintShareText(
    canvas,
    '模擬戶口只記錄虛擬研究下注，不涉及真實資金或投注。',
    ui.Offset(shareCardMargin, height - _footerHeight + 44),
    size: 24,
    color: shareCardFaint,
  );
  paintShareText(
    canvas,
    '僅供研究，非投注建議；過往模擬結果不代表將來表現。',
    ui.Offset(shareCardMargin, height - _footerHeight + 86),
    size: 24,
    color: shareCardFaint,
  );
}

/// Right-hand column of the selection badge and of a ledger row: both sit
/// beside text on the left, so they are bounded rather than card-wide.
const _badgePriceLeft = shareCardMargin + 700;
const _badgePriceWidth =
    shareCardWidth - shareCardMargin - 28 - _badgePriceLeft;
const _entryRightLeft = shareCardMargin + 660;
const _entryRightWidth =
    shareCardWidth - shareCardMargin - 28 - _entryRightLeft;

/// Selection chip of a single-bet card: what was backed, at what price.
void _paintBadge(ui.Canvas canvas, SimulatedTrade trade, double top) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        shareCardMargin,
        top,
        shareCardWidth - 2 * shareCardMargin,
        _badgeHeight,
      ),
      const ui.Radius.circular(28),
    ),
    ui.Paint()..color = const ui.Color(0x1F42E695),
  );
  paintShareText(
    canvas,
    trade.selectionText,
    ui.Offset(shareCardMargin + 32, top + 26),
    size: 40,
    weight: FontWeight.w900,
    color: shareCardGreen,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 300,
  );
  paintShareText(
    canvas,
    '@ ${trade.odds.toStringAsFixed(2)}',
    ui.Offset(_badgePriceLeft, top + 28),
    size: 38,
    weight: FontWeight.w900,
    align: TextAlign.right,
    maxWidth: _badgePriceWidth,
  );
}

/// Width the label of a figure row may take before it is ellipsised.
const _labelWidth = 500.0;

/// Left edge of the right-hand column, so a long value is cut off rather than
/// drawn over the label beside it.
const _valueLeft = shareCardMargin + _labelWidth + 16;
const _valueWidth = shareCardWidth - shareCardMargin - _valueLeft;

void _paintRow(ui.Canvas canvas, _Row row, double top) {
  paintShareText(
    canvas,
    row.label,
    ui.Offset(shareCardMargin, top),
    size: 28,
    color: const ui.Color(0xAAFFFFFF),
    maxWidth: _labelWidth,
  );
  paintShareText(
    canvas,
    row.value,
    ui.Offset(_valueLeft, top),
    size: 28,
    weight: FontWeight.w700,
    color: row.colour,
    align: TextAlign.right,
    maxWidth: _valueWidth,
  );
}

void _paintEntry(ui.Canvas canvas, SimulatedTrade trade, double top) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        shareCardMargin,
        top,
        shareCardWidth - 2 * shareCardMargin,
        108,
      ),
      const ui.Radius.circular(24),
    ),
    ui.Paint()..color = const ui.Color(0x14FFFFFF),
  );
  paintShareText(
    canvas,
    '${trade.leagueName} · ${shareTime(trade.matchDate)}',
    ui.Offset(shareCardMargin + 28, top + 14),
    size: 22,
    color: shareCardMuted,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 300,
  );
  paintShareText(
    canvas,
    trade.subject,
    ui.Offset(shareCardMargin + 28, top + 42),
    size: 30,
    weight: FontWeight.w800,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 320,
  );
  paintShareText(
    canvas,
    '${trade.selectionText} @${trade.odds.toStringAsFixed(2)} · '
    '注 ${_money(trade.stake)}',
    ui.Offset(shareCardMargin + 28, top + 76),
    size: 22,
    color: shareCardGreen,
    weight: FontWeight.w700,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 320,
  );
  paintShareText(
    canvas,
    _outcomeLabel(trade),
    ui.Offset(_entryRightLeft, top + 30),
    size: 30,
    weight: FontWeight.w900,
    color: _outcomeColour(trade),
    align: TextAlign.right,
    maxWidth: _entryRightWidth,
  );
  paintShareText(
    canvas,
    trade.status == 'settled' && trade.actualTotalCorners != null
        ? '實際 ${trade.actualTotalCorners} 個角球'
        : trade.status == 'settled'
        ? '已結算'
        : '待賽果',
    ui.Offset(_entryRightLeft, top + 70),
    size: 22,
    color: shareCardMuted,
    align: TextAlign.right,
    maxWidth: _entryRightWidth,
  );
}

String _outcomeLabel(SimulatedTrade trade) {
  final profit = trade.profit;
  if (trade.status != 'settled' || profit == null) {
    return '待結算';
  }
  return '${profit >= 0 ? '+' : '-'}${_money(profit.abs())}';
}

ui.Color _outcomeColour(SimulatedTrade trade) {
  final profit = trade.profit;
  if (trade.status != 'settled' || profit == null) {
    return _pendingColour;
  }
  return profit >= 0 ? shareCardGreen : _lossColour;
}

List<_Row> _tradeRows(SimulatedTrade trade) {
  final market = trade.marketProbability;
  return [
    _Row('注碼', _money(trade.stake)),
    _Row('中則可得', _money(trade.stake * trade.odds)),
    _Row(
      '模型機率',
      '${(trade.modelWinProbability * 100).toStringAsFixed(1)}%',
      colour: shareCardGreen,
    ),
    _Row(
      '市場公平機率',
      market == null ? '未紀錄' : '${(market * 100).toStringAsFixed(1)}%',
    ),
    _Row('模型期望值', '${(trade.expectedValue * 100).toStringAsFixed(1)}%'),
    _Row('模型信心', trade.confidence.isEmpty ? '未紀錄' : trade.confidence),
    if (trade.status == 'settled')
      _Row(
        '賽果',
        trade.actualTotalCorners == null
            ? '已結算'
            : '${trade.actualTotalCorners} 個角球',
      ),
    _Row(
      trade.status == 'settled' ? '盈虧' : '狀態',
      trade.status == 'settled' ? _outcomeLabel(trade) : '待賽果結算',
      colour: _outcomeColour(trade),
    ),
  ];
}

List<_Row> _summaryRows(SimulationLedger ledger) => [
  _Row('戶口價值', _money(ledger.balance)),
  _Row('可用餘額', _money(ledger.available)),
  _Row(
    '累計盈虧',
    '${ledger.profit >= 0 ? '+' : '-'}${_money(ledger.profit.abs())}',
    colour: ledger.profit >= 0 ? shareCardGreen : _lossColour,
  ),
  _Row(
    'ROI（已結算）',
    ledger.hasSettled ? '${(ledger.roi * 100).toStringAsFixed(2)}%' : '未有已結算賽果',
  ),
  _Row(
    '命中率',
    ledger.wins + ledger.losses == 0
        ? '未有已結算賽果'
        : '${(ledger.hitRate * 100).toStringAsFixed(1)}%'
              '（${ledger.wins}／${ledger.wins + ledger.losses}）',
  ),
  _Row('未結算', '${ledger.openCount} 注 · ${_money(ledger.openStake)}'),
  _Row(
    '最大回撤',
    ledger.hasSettled
        ? '${(ledger.maximumDrawdown * 100).toStringAsFixed(1)}%'
        : '未有已結算賽果',
  ),
];

String _money(double value) => value.toStringAsFixed(2);

class _Row {
  const _Row(this.label, this.value, {this.colour = shareCardWhite});

  final String label;
  final String value;
  final ui.Color colour;
}
