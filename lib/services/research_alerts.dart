/// Shared shape of every pick the app is willing to put in front of the user.
///
/// Football corners and racing win pools reach the same summary card, so both
/// describe themselves through this interface instead of the card knowing about
/// either model.
abstract class ResearchAlert {
  /// Where the pick sits: the league, or the venue and race number.
  String get context;

  /// Who the pick is about: both clubs, or the horse.
  String get subject;

  /// Market and selection, e.g. `角球 9.5 大` or `獨贏 7 號`.
  String get market;

  /// Quoted HKJC odds the edge was measured against.
  double get odds;

  /// Expected profit per unit stake at [odds].
  double get edge;

  /// Model trust in the pick, never a win probability.
  double get confidence;
  String get confidenceLabel;

  /// Kick-off or post time; picks are dropped once it passes.
  DateTime get startTime;
}

/// Plain-text version of the summary, for sharing where an image cannot go.
///
/// Both branches state the research-only nature, so a forwarded message never
/// reads as a betting instruction.
String buildAlertShareText({
  required List<ResearchAlert> alerts,
  required DateTime asOf,
}) {
  final lines = <String>['睿測 · 模型推介摘要', _stamp(asOf)];
  if (alerts.isEmpty) {
    lines
      ..add('')
      ..add('今日無推介：沒有場次通過模型門檻。');
  } else {
    lines.add('');
    for (var index = 0; index < alerts.length; index++) {
      final alert = alerts[index];
      lines
        ..add('${index + 1}. ${alert.context} · ${alert.subject}')
        ..add(
          '   ${alert.market} @${alert.odds.toStringAsFixed(2)} · '
          '信心 ${alert.confidenceLabel} · '
          '${_time(alert.startTime)} 開始',
        );
    }
  }
  lines
    ..add('')
    ..add('僅供研究，非投注建議。');
  return lines.join('\n');
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
