import 'dart:convert';
import 'dart:io';

import 'package:edgewise/services/drive_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup files are named so a Drive folder sorts by time', () {
    final name = DriveBackupService.backupFileName(
      DateTime(2026, 9, 8, 4, 5, 6),
    );

    expect(name, 'edgewise-research-20260908-040506.json');
  });

  test('the backup is written verbatim so its checksum survives', () async {
    final directory = await Directory.systemTemp.createTemp('drive-backup');
    addTearDown(() => directory.delete(recursive: true));
    final encoded = jsonEncode({'app': 'EdgeWise', 'schemaVersion': 1});

    final file = await DriveBackupService(
      directory: directory,
    ).writeBackupFile(encoded, asOf: DateTime(2026, 9, 8, 4, 5, 6));

    expect(await file.readAsString(), encoded);
    expect(file.path, endsWith('edgewise-research-20260908-040506.json'));
  });

  test('a backup of this app is accepted', () {
    final encoded = jsonEncode({
      'app': 'EdgeWise',
      'schemaVersion': 1,
      'simulatedTrades': const <Object?>[],
    });

    final read = DriveBackupService.readBackup(
      utf8.encode(encoded),
      fileName: 'edgewise-research-20260908-040506.json',
    );

    expect(read.content, encoded);
    expect(read.fileName, 'edgewise-research-20260908-040506.json');
  });

  test('another app\'s JSON is refused instead of failing on checksum', () {
    expect(
      () => DriveBackupService.readBackup(
        utf8.encode(jsonEncode({'app': 'SomethingElse'})),
        fileName: 'other.json',
      ),
      throwsA(
        isA<DriveBackupException>().having(
          (error) => error.message,
          'message',
          contains('不是睿測研究備份檔'),
        ),
      ),
    );
  });

  test('a half-synced Drive placeholder is refused by name of its problem', () {
    expect(
      () => DriveBackupService.readBackup(
        utf8.encode('not json at all'),
        fileName: 'placeholder.json',
      ),
      throwsA(
        isA<DriveBackupException>().having(
          (error) => error.message,
          'message',
          contains('不是 JSON'),
        ),
      ),
    );
    expect(
      () => DriveBackupService.readBackup(const [
        0xC3,
        0x28,
      ], fileName: 'binary.json'),
      throwsA(
        isA<DriveBackupException>().having(
          (error) => error.message,
          'message',
          contains('UTF-8'),
        ),
      ),
    );
  });
}
