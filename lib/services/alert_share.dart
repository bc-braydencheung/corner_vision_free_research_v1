import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'alert_share_image.dart';
import 'research_alerts.dart';

/// Hands the current picks to WhatsApp (or any other target) as one card image.
///
/// WhatsApp's own `wa.me` link can only carry text, so the image goes through
/// the system share sheet — where WhatsApp is a target — with the text version
/// attached as the message body for anywhere that cannot take a picture.
class AlertShareService {
  const AlertShareService();

  Future<void> share({
    required List<ResearchAlert> alerts,
    required DateTime asOf,
  }) async {
    final image = await renderAlertShareImage(alerts: alerts, asOf: asOf);
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/share',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/${_fileName(asOf)}');
    await file.writeAsBytes(image.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: buildAlertShareText(alerts: alerts, asOf: asOf),
        subject: '睿測 · 模型推介摘要',
      ),
    );
  }

  static String _fileName(DateTime asOf) {
    final local = asOf.toLocal();
    final stamp =
        '${local.year}${_two(local.month)}${_two(local.day)}'
        '-${_two(local.hour)}${_two(local.minute)}';
    return 'edgewise-picks-$stamp.png';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
