import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'research_alerts.dart';

/// Card image of the current picks, drawn for sharing outside the app.
///
/// Painted straight onto a canvas rather than captured from the widget tree, so
/// the shared picture is identical whatever the phone's screen size, theme or
/// scroll position is, and so it can be verified in tests without a frame.
class AlertShareImage {
  const AlertShareImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

const _width = 1080.0;
const _margin = 64.0;
const _rowHeight = 148.0;

/// Renders the summary as a PNG.
///
/// [alerts] arrives already filtered by the models; nothing is added here, and
/// an empty list is drawn as an explicit "no picks today" card rather than an
/// empty frame, so a shared image never implies a pick that does not exist.
Future<AlertShareImage> renderAlertShareImage({
  required List<ResearchAlert> alerts,
  required DateTime asOf,
}) async {
  final headerHeight = 232.0;
  final footerHeight = 132.0;
  final bodyHeight = alerts.isEmpty ? 168.0 : alerts.length * _rowHeight;
  final height = headerHeight + bodyHeight + footerHeight;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, _width, height));
  final background = ui.Paint()
    ..shader = ui.Gradient.linear(
      const ui.Offset(0, 0),
      ui.Offset(_width, height),
      const [ui.Color(0xFF0E3325), ui.Color(0xFF04120C)],
    );
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, _width, height), background);

  _paint(
    canvas,
    '睿測',
    const ui.Offset(_margin, 62),
    size: 62,
    weight: FontWeight.w900,
  );
  _paint(
    canvas,
    '模型推介摘要 · 足球角球 ／ 賽馬',
    const ui.Offset(_margin, 140),
    size: 30,
    color: const ui.Color(0xFF42E695),
    weight: FontWeight.w700,
  );
  _paint(
    canvas,
    _stamp(asOf),
    const ui.Offset(_margin, 182),
    size: 26,
    color: const ui.Color(0x99FFFFFF),
  );
  canvas.drawRect(
    ui.Rect.fromLTWH(_margin, headerHeight - 26, _width - 2 * _margin, 2),
    ui.Paint()..color = const ui.Color(0x22FFFFFF),
  );

  var top = headerHeight;
  if (alerts.isEmpty) {
    _paint(
      canvas,
      '今日無推介',
      ui.Offset(_margin, top + 16),
      size: 44,
      weight: FontWeight.w900,
    );
    _paint(
      canvas,
      '沒有場次通過模型門檻，寧可不出訊號。',
      ui.Offset(_margin, top + 84),
      size: 26,
      color: const ui.Color(0xAAFFFFFF),
    );
  } else {
    for (var index = 0; index < alerts.length; index++) {
      final alert = alerts[index];
      final rowTop = top + index * _rowHeight;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(_margin, rowTop + 10, _width - 2 * _margin, 124),
          const ui.Radius.circular(24),
        ),
        ui.Paint()..color = const ui.Color(0x14FFFFFF),
      );
      _paint(
        canvas,
        '${index + 1}',
        ui.Offset(_margin + 30, rowTop + 46),
        size: 40,
        color: const ui.Color(0xFFFFC857),
        weight: FontWeight.w900,
      );
      _paint(
        canvas,
        '${alert.context} · ${_time(alert.startTime)}',
        ui.Offset(_margin + 92, rowTop + 30),
        size: 24,
        color: const ui.Color(0x99FFFFFF),
      );
      _paint(
        canvas,
        alert.subject,
        ui.Offset(_margin + 92, rowTop + 60),
        size: 34,
        weight: FontWeight.w800,
        maxWidth: _width - 2 * _margin - 300,
      );
      _paint(
        canvas,
        '${alert.market} @${alert.odds.toStringAsFixed(2)}',
        ui.Offset(_margin + 92, rowTop + 100),
        size: 26,
        color: const ui.Color(0xFF42E695),
        weight: FontWeight.w700,
      );
      _paint(
        canvas,
        '信心 ${alert.confidenceLabel}',
        ui.Offset(_width - _margin - 200, rowTop + 60),
        size: 30,
        weight: FontWeight.w800,
      );
    }
  }

  _paint(
    canvas,
    '僅供研究，非投注建議；賠率為讀取時的馬會公開報價。',
    ui.Offset(_margin, height - footerHeight + 34),
    size: 24,
    color: const ui.Color(0x88FFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width.round(), height.round());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return AlertShareImage(
    bytes: data!.buffer.asUint8List(),
    width: _width.round(),
    height: height.round(),
  );
}

void _paint(
  ui.Canvas canvas,
  String text,
  ui.Offset offset, {
  required double size,
  ui.Color color = const ui.Color(0xFFFFFFFF),
  FontWeight weight = FontWeight.w500,
  double? maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth ?? _width - 2 * _margin);
  painter.paint(canvas, offset);
  painter.dispose();
}

String _stamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _time(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.month)}/${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
