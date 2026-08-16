import '../core/combinatorics.dart';
import 'draw.dart';

class CsvParseResult {
  const CsvParseResult(this.draws, this.errors);

  final List<Draw> draws;
  final List<String> errors;
}

/// Parses a draw history CSV.
///
/// Expected columns (header optional, order fixed):
/// `label,date,n1,n2,n3,n4,n5,n6[,extra][,jackpotWinners]`
///
/// The importer exists because the app must never pretend that a bundled
/// dataset is official: real analysis requires the user's own copy of the
/// published results.
class HistoryCsv {
  static CsvParseResult parse(String content) {
    final draws = <Draw>[];
    final errors = <String>[];
    final lines = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final cells = lines[i].split(',').map((c) => c.trim()).toList();
      if (cells.length < 8) {
        errors.add('Line ${i + 1}: expected at least 8 columns');
        continue;
      }
      if (i == 0 && int.tryParse(cells[2]) == null) continue;

      final numbers = <int>[];
      var bad = false;
      for (var k = 2; k < 8; k++) {
        final v = int.tryParse(cells[k]);
        if (v == null || v < 1 || v > kBallCount) {
          bad = true;
          break;
        }
        numbers.add(v);
      }
      if (bad || numbers.toSet().length != kPickCount) {
        errors.add('Line ${i + 1}: invalid number set');
        continue;
      }
      final date = DateTime.tryParse(cells[1]);
      if (date == null) {
        errors.add('Line ${i + 1}: unparseable date "${cells[1]}"');
        continue;
      }
      draws.add(
        Draw(
          label: cells[0],
          date: date,
          numbers: numbers..sort(),
          extra: cells.length > 8 ? int.tryParse(cells[8]) : null,
          jackpotWinners: cells.length > 9 ? double.tryParse(cells[9]) : null,
        ),
      );
    }
    return CsvParseResult(draws, errors);
  }

  static String write(List<Draw> draws) {
    final sb = StringBuffer(
      'label,date,n1,n2,n3,n4,n5,n6,extra,jackpotWinners\n',
    );
    for (final d in draws) {
      sb.writeln(
        '${d.label},${d.date.toIso8601String().substring(0, 10)},'
        '${d.sorted.join(',')},${d.extra ?? ''},${d.jackpotWinners ?? ''}',
      );
    }
    return sb.toString();
  }
}
