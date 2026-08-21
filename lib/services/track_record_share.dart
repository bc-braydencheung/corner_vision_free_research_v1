import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'track_record.dart';
import 'track_record_share_image.dart';

/// Hands the public record to WhatsApp (or any other target) as one card image.
///
/// The image carries the figures; the text body repeats only what a target that
/// cannot take a picture still needs, disclosure included.
class TrackRecordShareService {
  const TrackRecordShareService();

  Future<void> share({
    required TrackRecordReport report,
    required DateTime asOf,
  }) async {
    final image = await renderTrackRecordShareImage(report: report, asOf: asOf);
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/share',
    );
    await directory.create(recursive: true);
    final file = File('${directory.path}/${_fileName(asOf)}');
    await file.writeAsBytes(image.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: buildTrackRecordShareText(report: report, asOf: asOf),
        subject: '睿測 · 至今紀錄',
      ),
    );
  }

  static String _fileName(DateTime asOf) {
    final local = asOf.toLocal();
    final stamp =
        '${local.year}${_two(local.month)}${_two(local.day)}'
        '-${_two(local.hour)}${_two(local.minute)}';
    return 'edgewise-record-$stamp.png';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// Text version of the record, used wherever an image cannot be delivered.
String buildTrackRecordShareText({
  required TrackRecordReport report,
  required DateTime asOf,
}) {
  final local = asOf.toLocal();
  final lines = <String>[
    '睿測 · 至今紀錄（${local.year}-${_pad(local.month)}-${_pad(local.day)}）',
    '推介 ${report.recommended} 個，已結算 ${report.settled} 個',
    report.hasSettled
        ? '命中率 ${(report.hitRate * 100).toStringAsFixed(1)}%'
        : '命中率：未有已結算賽果',
    report.brierSamples == 0
        ? 'Brier：樣本不足'
        : 'Brier 模型 ${report.brier.toStringAsFixed(4)} ／ '
              '盤口 ${report.marketBrier.toStringAsFixed(4)}',
    report.clvSamples == 0
        ? '平均 CLV：樣本不足'
        : '平均 CLV ${(report.meanClosingLineValue * 100).toStringAsFixed(2)}%'
              '（${report.clvSamples} 個樣本）',
    report.hasSettled
        ? '累計研究單位 ${report.netUnits.toStringAsFixed(2)}'
        : '累計研究單位：未有已結算賽果',
    report.verdict,
    '僅供研究，非投注建議；研究單位不代表金額。',
  ];
  return lines.join('\n');
}

String _pad(int value) => value.toString().padLeft(2, '0');
