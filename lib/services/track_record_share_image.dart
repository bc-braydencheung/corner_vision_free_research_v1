import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'share_canvas.dart';
import 'track_record.dart';

const _headerHeight = 232.0;
const _footerHeight = 168.0;
const _rowHeight = 46.0;
const _blockGap = 30.0;
const _entryHeight = 118.0;

/// How many of the newest recommendations are listed on the card.
const trackRecordShareEntries = 5;

/// The newest recommendations the card lists, observations excluded.
List<TrackRecordEntry> trackRecordShareListing(TrackRecordReport report) =>
    (report.entries.where((entry) => entry.recommended).toList()
          ..sort((left, right) => right.matchDate.compareTo(left.matchDate)))
        .take(trackRecordShareEntries)
        .toList();

/// Renders the public record as a PNG at [shareCardScale] resolution.
///
/// Only what the report already carries is drawn: an unmeasurable figure is
/// printed as `樣本不足` rather than filled with a flattering number, and the
/// listed rows are the newest recommendations only, so a shared card never
/// implies a longer record than the ledger holds.
Future<ShareCardImage> renderTrackRecordShareImage({
  required TrackRecordReport report,
  required DateTime asOf,
}) async {
  final listed = trackRecordShareListing(report);
  final performance = _performanceRows(report);
  final priceRows = _priceRows(report);
  final unitRows = _unitRows(report);
  final bodyHeight =
      68.0 +
      (performance.length + priceRows.length + unitRows.length) * _rowHeight +
      3 * _blockGap +
      (listed.isEmpty ? 74.0 : 44.0 + listed.length * _entryHeight);
  final height = _headerHeight + bodyHeight + _footerHeight;
  final recorder = ui.PictureRecorder();
  final canvas = beginShareCard(recorder, height);

  paintShareText(
    canvas,
    '睿測',
    const ui.Offset(shareCardMargin, 62),
    size: 62,
    weight: FontWeight.w900,
  );
  paintShareText(
    canvas,
    '至今紀錄 · 足球角球推介',
    const ui.Offset(shareCardMargin, 140),
    size: 30,
    color: shareCardGreen,
    weight: FontWeight.w700,
  );
  paintShareText(
    canvas,
    shareStamp(asOf),
    const ui.Offset(shareCardMargin, 182),
    size: 26,
    color: shareCardMuted,
  );
  paintShareRule(canvas, _headerHeight - 26);

  var top = _headerHeight;
  paintShareText(
    canvas,
    report.verdict,
    ui.Offset(shareCardMargin, top),
    size: 28,
    color: const ui.Color(0xCCFFFFFF),
    weight: FontWeight.w600,
  );
  top += 68;

  top = _paintBlock(canvas, '預測表現（機率準唔準）', performance, top);
  top = _paintBlock(canvas, '價格表現（收盤價 CLV）', priceRows, top);
  top = _paintBlock(canvas, '研究單位（非金錢）', unitRows, top);

  if (listed.isEmpty) {
    paintShareText(
      canvas,
      '至今未有推介入帳',
      ui.Offset(shareCardMargin, top),
      size: 32,
      weight: FontWeight.w800,
    );
  } else {
    paintShareText(
      canvas,
      '最近 ${listed.length} 個推介',
      ui.Offset(shareCardMargin, top),
      size: 26,
      color: shareCardGreen,
      weight: FontWeight.w700,
    );
    top += 44;
    for (var index = 0; index < listed.length; index++) {
      _paintEntry(canvas, listed[index], top + index * _entryHeight);
    }
  }

  paintShareText(
    canvas,
    '僅供研究，非投注建議；本 App 無投注、付款或模擬戶口。',
    ui.Offset(shareCardMargin, height - _footerHeight + 40),
    size: 24,
    color: shareCardFaint,
  );
  paintShareText(
    canvas,
    '「研究單位」只是每次一注的假設計數，不代表任何金額或收益。',
    ui.Offset(shareCardMargin, height - _footerHeight + 82),
    size: 24,
    color: shareCardFaint,
  );
  return endShareCard(recorder, height);
}

double _paintBlock(
  ui.Canvas canvas,
  String label,
  List<_Row> rows,
  double top,
) {
  paintShareText(
    canvas,
    label,
    ui.Offset(shareCardMargin, top),
    size: 26,
    color: shareCardGreen,
    weight: FontWeight.w700,
  );
  var rowTop = top + 40;
  for (final row in rows) {
    paintShareText(
      canvas,
      row.label,
      ui.Offset(shareCardMargin, rowTop),
      size: 28,
      color: const ui.Color(0xAAFFFFFF),
      maxWidth: 460,
    );
    paintShareText(
      canvas,
      row.value,
      ui.Offset(shareCardMargin, rowTop),
      size: 28,
      weight: FontWeight.w700,
      align: TextAlign.right,
    );
    rowTop += _rowHeight;
  }
  return rowTop + _blockGap - 10;
}

void _paintEntry(ui.Canvas canvas, TrackRecordEntry entry, double top) {
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      ui.Rect.fromLTWH(
        shareCardMargin,
        top,
        shareCardWidth - 2 * shareCardMargin,
        100,
      ),
      const ui.Radius.circular(24),
    ),
    ui.Paint()..color = const ui.Color(0x14FFFFFF),
  );
  paintShareText(
    canvas,
    '${entry.leagueName} · ${shareTime(entry.matchDate)}',
    ui.Offset(shareCardMargin + 28, top + 16),
    size: 22,
    color: shareCardMuted,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 260,
  );
  paintShareText(
    canvas,
    '${entry.homeTeam} 對 ${entry.awayTeam}',
    ui.Offset(shareCardMargin + 28, top + 46),
    size: 30,
    weight: FontWeight.w800,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 300,
  );
  paintShareText(
    canvas,
    '${entry.line} ${entry.directionLabel} '
    '@${entry.takenOdds.toStringAsFixed(2)}',
    ui.Offset(shareCardMargin, top + 30),
    size: 28,
    color: shareCardGreen,
    weight: FontWeight.w700,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 28,
    align: TextAlign.right,
  );
  paintShareText(
    canvas,
    _outcome(entry),
    ui.Offset(shareCardMargin, top + 62),
    size: 24,
    color: shareCardMuted,
    maxWidth: shareCardWidth - 2 * shareCardMargin - 28,
    align: TextAlign.right,
  );
}

String _outcome(TrackRecordEntry entry) {
  final result = entry.won;
  if (result == null) {
    return '未結算';
  }
  return '${entry.actualTotalCorners} 個角球 · ${result ? '中' : '不中'}';
}

List<_Row> _performanceRows(TrackRecordReport report) => [
  _Row('推介 ／ 已結算', '${report.recommended} ／ ${report.settled}'),
  _Row(
    '命中率',
    report.hasSettled
        ? '${(report.hitRate * 100).toStringAsFixed(1)}%'
        : '未有已結算賽果',
  ),
  _Row(
    'Brier（模型 ／ 盤口）',
    report.brierSamples == 0
        ? '樣本不足'
        : '${report.brier.toStringAsFixed(4)} ／ '
              '${report.marketBrier.toStringAsFixed(4)}',
  ),
  _Row(
    '是否勝過盤口',
    report.brierSamples < 20
        ? '樣本不足 20'
        : report.beatsMarketBrier
        ? '是'
        : '否',
  ),
];

List<_Row> _priceRows(TrackRecordReport report) => [
  _Row('有收盤價樣本', '${report.clvSamples} 個'),
  _Row(
    '平均 CLV',
    report.clvSamples == 0
        ? '樣本不足'
        : '${(report.meanClosingLineValue * 100).toStringAsFixed(2)}%',
  ),
  _Row(
    '打敗收盤價比率',
    report.clvSamples == 0
        ? '樣本不足'
        : '${(report.beatClosingRate * 100).toStringAsFixed(1)}%',
  ),
];

List<_Row> _unitRows(TrackRecordReport report) => [
  _Row(
    '累計單位',
    report.hasSettled ? report.netUnits.toStringAsFixed(2) : '未有已結算賽果',
  ),
  _Row(
    '最大回撤',
    report.hasSettled
        ? report.maximumDrawdownUnits.toStringAsFixed(2)
        : '未有已結算賽果',
  ),
];

class _Row {
  const _Row(this.label, this.value);

  final String label;
  final String value;
}
