import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/simulated_trade.dart';

/// Format tag written into every export, and required on import.
const simulationBackupSchema = 'edgewise-simulation-account';
const simulationBackupSchemaVersion = 1;

/// Raised when a chosen file is not a simulation export this build understands.
///
/// The message is user-facing on purpose: a rejected import must say what was
/// wrong with the file rather than silently repairing or dropping rows.
class SimulationImportException implements Exception {
  const SimulationImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Rows read back out of an export file.
class SimulationImport {
  const SimulationImport({
    required this.trades,
    required this.bankroll,
    required this.fileName,
  });

  final List<SimulatedTrade> trades;

  /// Starting balance the export was taken with, when it carried one.
  final double? bankroll;
  final String fileName;
}

/// Writes the simulated ledger to a JSON file and reads one back.
///
/// Export goes through the platform share sheet rather than the clipboard, so
/// the file can be saved or sent as a file; import goes through the file
/// picker, so any saved export can be restored on another device.
class SimulationBackupService {
  const SimulationBackupService();

  /// The exported document, pretty-printed so it stays readable.
  String encode({
    required List<SimulatedTrade> trades,
    required double bankroll,
    required DateTime asOf,
  }) {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schema': simulationBackupSchema,
      'schemaVersion': simulationBackupSchemaVersion,
      'app': 'EdgeWise',
      'exportedAt': asOf.toUtc().toIso8601String(),
      'bankroll': bankroll,
      'trades': trades.map((trade) => trade.toJson()).toList(),
    });
  }

  /// Parses an export document, rejecting anything it cannot read exactly.
  SimulationImport decode(String content, {String fileName = ''}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException {
      throw const SimulationImportException('檔案不是有效的 JSON。');
    }
    if (decoded is! Map) {
      throw const SimulationImportException('JSON 最外層必須是物件。');
    }
    final payload = decoded.cast<String, Object?>();
    final schema = payload['schema'];
    if (schema != simulationBackupSchema) {
      throw const SimulationImportException('這不是模擬戶口匯出檔（schema 不符）。');
    }
    final version = payload['schemaVersion'];
    if (version is! num || version > simulationBackupSchemaVersion) {
      throw const SimulationImportException('匯出檔版本較新，此版本 App 無法讀取。');
    }
    final rows = payload['trades'];
    if (rows is! List) {
      throw const SimulationImportException('缺少 trades 陣列。');
    }
    final trades = <SimulatedTrade>[];
    final seen = <String>{};
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (row is! Map) {
        throw SimulationImportException('第 ${index + 1} 筆記錄不是物件。');
      }
      final SimulatedTrade trade;
      try {
        trade = SimulatedTrade.fromJson(row.cast<String, Object?>());
      } on Object {
        throw SimulationImportException('第 ${index + 1} 筆記錄欄位不完整或格式錯誤。');
      }
      if (!trade.odds.isFinite ||
          trade.odds <= 1 ||
          !trade.stake.isFinite ||
          trade.stake <= 0 ||
          !trade.line.isFinite ||
          trade.line < 0 ||
          (trade.status != 'open' && trade.status != 'settled')) {
        throw SimulationImportException('第 ${index + 1} 筆記錄的賠率、注碼、盤口或狀態無效。');
      }
      if (trade.modelWinProbability < 0 ||
          trade.modelWinProbability > 1 ||
          (trade.marketProbability != null &&
              (trade.marketProbability! < 0 || trade.marketProbability! > 1))) {
        throw SimulationImportException('第 ${index + 1} 筆記錄的機率不在 0 至 1 之間。');
      }
      // A settled row without a profit would read as an open one and be settled
      // twice, so the file is rejected instead of being reinterpreted.
      if (trade.status == 'settled' && trade.profit == null) {
        throw SimulationImportException('第 ${index + 1} 筆記錄標示已結算但沒有盈虧。');
      }
      if (trade.id.isEmpty || !seen.add(trade.id)) {
        throw SimulationImportException('第 ${index + 1} 筆記錄的 id 空白或重複。');
      }
      trades.add(trade);
    }
    final bankroll = payload['bankroll'];
    return SimulationImport(
      trades: trades,
      bankroll: bankroll is num && bankroll > 0 ? bankroll.toDouble() : null,
      fileName: fileName,
    );
  }

  /// Writes the export to app storage and offers it through the share sheet.
  Future<File> export({
    required List<SimulatedTrade> trades,
    required double bankroll,
    required DateTime asOf,
  }) async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/export',
    );
    await directory.create(recursive: true);
    final local = asOf.toLocal();
    final stamp =
        '${local.year}${_two(local.month)}${_two(local.day)}'
        '-${_two(local.hour)}${_two(local.minute)}${_two(local.second)}';
    final file = File('${directory.path}/edgewise-simulation-$stamp.json');
    await file.writeAsString(
      encode(trades: trades, bankroll: bankroll, asOf: asOf),
      flush: true,
    );
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        subject: '睿測 · 模擬戶口匯出',
        text: '睿測模擬戶口記錄（${trades.length} 注，虛擬研究用）',
      ),
    );
    return file;
  }

  /// Lets the user pick a JSON export; null when they cancel the picker.
  Future<SimulationImport?> importFromFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '選擇模擬戶口匯出檔（JSON）',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null) {
      return null;
    }
    final String content;
    try {
      content = utf8.decode(await picked.readAsBytes(), allowMalformed: false);
    } on FormatException {
      throw const SimulationImportException('檔案不是 UTF-8 文字，無法讀取。');
    }
    return decode(content, fileName: picked.name);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
