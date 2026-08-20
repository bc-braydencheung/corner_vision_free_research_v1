import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Card image drawn for sharing outside the app.
class ShareCardImage {
  const ShareCardImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Width of a share card in layout units.
const shareCardWidth = 1080.0;
const shareCardMargin = 64.0;

/// Pixels drawn per layout unit.
///
/// Every card lays out in one set of units while the canvas is rasterised at a
/// multiple of it, so glyphs and strokes are drawn at the higher resolution
/// instead of being an upscaled 1080 px bitmap.
const shareCardScale = 3.0;

const shareCardWhite = ui.Color(0xFFFFFFFF);
const shareCardGreen = ui.Color(0xFF42E695);
const shareCardMuted = ui.Color(0x99FFFFFF);
const shareCardFaint = ui.Color(0x88FFFFFF);

/// Starts a card of [height] layout units, scaled up and filled with the
/// house gradient.
ui.Canvas beginShareCard(ui.PictureRecorder recorder, double height) {
  final canvas = ui.Canvas(
    recorder,
    ui.Rect.fromLTWH(
      0,
      0,
      shareCardWidth * shareCardScale,
      height * shareCardScale,
    ),
  );
  canvas.scale(shareCardScale);
  final background = ui.Paint()
    ..shader = ui.Gradient.linear(
      const ui.Offset(0, 0),
      ui.Offset(shareCardWidth, height),
      const [ui.Color(0xFF0E3325), ui.Color(0xFF04120C)],
    );
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, shareCardWidth, height), background);
  return canvas;
}

/// Encodes the recorded card as a PNG at [shareCardScale] resolution.
Future<ShareCardImage> endShareCard(
  ui.PictureRecorder recorder,
  double height,
) async {
  final picture = recorder.endRecording();
  final width = (shareCardWidth * shareCardScale).round();
  final pixelHeight = (height * shareCardScale).round();
  final image = await picture.toImage(width, pixelHeight);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return ShareCardImage(
    bytes: data!.buffer.asUint8List(),
    width: width,
    height: pixelHeight,
  );
}

/// Draws a horizontal rule across the card body.
void paintShareRule(ui.Canvas canvas, double top) {
  canvas.drawRect(
    ui.Rect.fromLTWH(
      shareCardMargin,
      top,
      shareCardWidth - 2 * shareCardMargin,
      2,
    ),
    ui.Paint()..color = const ui.Color(0x22FFFFFF),
  );
}

/// Draws one line of text, clipped to the card body unless [maxWidth] narrows
/// it further.
void paintShareText(
  ui.Canvas canvas,
  String text,
  ui.Offset offset, {
  required double size,
  ui.Color color = shareCardWhite,
  FontWeight weight = FontWeight.w500,
  double? maxWidth,
  TextAlign align = TextAlign.left,
}) {
  final width = maxWidth ?? shareCardWidth - 2 * shareCardMargin;
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(minWidth: align == TextAlign.left ? 0 : width, maxWidth: width);
  painter.paint(canvas, offset);
  painter.dispose();
}

String shareStamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String shareTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.month)}/${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
