import '../core/combinatorics.dart';

class Draw {
  const Draw({
    required this.label,
    required this.date,
    required this.numbers,
    this.extra,
    this.jackpotWinners,
  });

  final String label;
  final DateTime date;

  /// The six main numbers, ascending.
  final List<int> numbers;

  /// The extra (7th) number, when known.
  final int? extra;

  /// Number of first-division winning units, when known. Used by the crowd
  /// model calibration as an observation of `q(c)`.
  final double? jackpotWinners;

  bool get isValid =>
      numbers.length == kPickCount &&
      numbers.every((n) => n >= 1 && n <= kBallCount) &&
      numbers.toSet().length == kPickCount;

  List<int> get sorted => List<int>.of(numbers)..sort();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'label': label,
    'date': date.toIso8601String(),
    'numbers': numbers,
    'extra': extra,
    'jackpotWinners': jackpotWinners,
  };

  static Draw fromJson(Map<String, dynamic> json) => Draw(
    label: json['label'] as String,
    date: DateTime.parse(json['date'] as String),
    numbers: (json['numbers'] as List<dynamic>).map((e) => e as int).toList(),
    extra: json['extra'] as int?,
    jackpotWinners: (json['jackpotWinners'] as num?)?.toDouble(),
  );
}
