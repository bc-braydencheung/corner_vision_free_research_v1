import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Backup and restore of the whole research ledger through Google Drive.
///
/// The transfer goes through Android's own share sheet and document picker
/// rather than the Drive API, so the app never asks for a Google account, never
/// holds an OAuth token, and needs no paid developer plan. The cost of that
/// choice is that the app cannot list or overwrite files on Drive by itself:
/// the user chooses the destination once per backup.
class DriveBackupService {
  DriveBackupService({this.directory});

  /// Where backup files are written; the app documents directory when null.
  final Directory? directory;

  /// Writes [encoded] to a timestamped file inside app storage.
  ///
  /// Named so a folder of backups sorts chronologically and so a restore can
  /// tell two exports of the same day apart.
  Future<File> writeBackupFile(String encoded, {DateTime? asOf}) async {
    final base =
        directory ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/backup');
    await base.create(recursive: true);
    final file = File('${base.path}/${backupFileName(asOf ?? DateTime.now())}');
    await file.writeAsString(encoded, flush: true);
    return file;
  }

  static String backupFileName(DateTime asOf) {
    final local = asOf.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'edgewise-research-${local.year}${two(local.month)}'
        '${two(local.day)}-${two(local.hour)}${two(local.minute)}'
        '${two(local.second)}.json';
  }

  /// Offers the written backup to Drive (or any other target) via the share
  /// sheet.
  Future<File> backup(String encoded, {DateTime? asOf}) async {
    final file = await writeBackupFile(encoded, asOf: asOf);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: '睿測 · 研究備份',
        text: '睿測研究備份（模擬記錄、影子預測、快照，全部虛擬研究用）',
      ),
    );
    return file;
  }

  /// Reads a backup the user picks; null when they cancel.
  ///
  /// Google Drive shows up as a source in the system picker, so a file backed
  /// up on the old phone can be restored on a new one without any account
  /// linking inside the app.
  Future<DriveBackupFile?> pickBackup() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '選擇研究備份檔（JSON）',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) {
      return null;
    }
    return readBackup(await picked.readAsBytes(), fileName: picked.name);
  }

  /// Decodes picked bytes, refusing anything that is not this app's backup.
  ///
  /// The picker can hand back a placeholder or a partially synced Drive file,
  /// which decodes as text but is not a backup; failing here keeps the restore
  /// path from reporting a checksum error for a file that was never ours.
  static DriveBackupFile readBackup(
    List<int> bytes, {
    required String fileName,
  }) {
    final String content;
    try {
      content = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const DriveBackupException('檔案不是 UTF-8 文字，可能仍在 Drive 同步中。');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw const DriveBackupException('檔案不是 JSON，請選擇「備份到 Drive」產生的檔案。');
    }
    if (decoded is! Map || decoded['app'] != 'EdgeWise') {
      throw const DriveBackupException('這不是睿測研究備份檔。');
    }
    return DriveBackupFile(content: content, fileName: fileName);
  }
}

class DriveBackupFile {
  const DriveBackupFile({required this.content, required this.fileName});

  final String content;
  final String fileName;
}

class DriveBackupException implements Exception {
  const DriveBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
