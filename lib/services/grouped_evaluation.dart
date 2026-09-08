import 'dart:math';

import '../models/shadow_forecast.dart';

/// Minimum settled matches before a subset's interval is worth reading.
const groupedEvaluationMinimumSamples = 20;

/// Bootstrap resamples drawn per subset.
///
/// A few hundred resamples settle the percentile ends to the third decimal,
/// which is all the display shows, and keeps a full report inside one frame on
/// a phone.
const groupedEvaluationResamples = 400;

/// How the model scored against the market inside one subset of the ledger.
class GroupScore {
  const GroupScore({
    required this.dimension,
    required this.label,
    required this.samples,
    required this.modelBrier,
    required this.marketBrier,
    required this.gain,
    required this.gainLow,
    required this.gainHigh,
  });

  /// `league`, `line` or `lead` (time from capture to kick-off).
  final String dimension;

  /// Human label of the subset, e.g. `英超` or `6–24 小時`.
  final String label;
  final int samples;
  final double modelBrier;

  /// Brier of the margin-free market price on the same matches.
  final double marketBrier;

  /// Mean per-match Brier gain over the market; positive means sharper.
  final double gain;

  /// Percentile bootstrap bounds of [gain], 2.5% and 97.5%.
  final double gainLow;
  final double gainHigh;

  bool get sufficient => samples >= groupedEvaluationMinimumSamples;

  /// Whether the whole interval sits above zero.
  ///
  /// A positive [gain] on its own is the usual way a subset looks like an edge
  /// while being noise, so the interval, not the point estimate, decides.
  bool get positive => sufficient && gainLow > 0;

  String get verdict {
    if (!sufficient) {
      return '樣本不足（$samples／$groupedEvaluationMinimumSamples）';
    }
    if (positive) {
      return '勝過盤口';
    }
    return gainHigh < 0 ? '輸給盤口' : '未分勝負';
  }

  String get intervalLabel =>
      '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(4)} '
      '[${gainLow.toStringAsFixed(4)}, ${gainHigh.toStringAsFixed(4)}]';
}

/// The ledger split by league, by shown line and by how early it was captured.
class GroupedEvaluation {
  const GroupedEvaluation({
    required this.samples,
    required this.byLeague,
    required this.byLine,
    required this.byLeadTime,
    required this.message,
  });

  static const empty = GroupedEvaluation(
    samples: 0,
    byLeague: [],
    byLine: [],
    byLeadTime: [],
    message: '未有已結算且存有盤口價的前瞻紀錄，無法分組比較。',
  );

  /// Settled forecasts carrying both a model probability and a market price.
  final int samples;
  final List<GroupScore> byLeague;
  final List<GroupScore> byLine;
  final List<GroupScore> byLeadTime;
  final String message;

  List<GroupScore> get all => [...byLeague, ...byLine, ...byLeadTime];

  /// Subsets whose whole interval is above zero.
  List<GroupScore> get positiveGroups =>
      all.where((group) => group.positive).toList();
}

/// Scores the model against the market inside each league, line and lead-time
/// bucket, with a bootstrap interval per subset.
///
/// The overall gate compares one pooled number, which hides both a subset that
/// is genuinely sharper and a subset that is paid for by the rest. Every subset
/// is scored on the same records the pooled comparison uses — settled, with a
/// model probability and the margin-free price of the same line written down
/// before kick-off — so nothing here is refit and no subset is scored on prices
/// the app never stored.
GroupedEvaluation evaluateGroups(
  List<ShadowForecast> records, {
  int resamples = groupedEvaluationResamples,
  int seed = 7,
}) {
  final settled = records
      .where(
        (record) =>
            record.actualTotalCorners != null &&
            record.over9_5Probability != null &&
            record.marketOverProbability != null,
      )
      .toList(growable: false);
  if (settled.isEmpty) {
    return GroupedEvaluation.empty;
  }
  final random = Random(seed);
  List<GroupScore> score(
    String dimension,
    String? Function(ShadowForecast) label,
  ) {
    final buckets = <String, List<ShadowForecast>>{};
    for (final record in settled) {
      final key = label(record);
      if (key == null) {
        continue;
      }
      buckets.putIfAbsent(key, () => []).add(record);
    }
    final scores =
        buckets.entries
            .map(
              (entry) => _score(
                dimension: dimension,
                label: entry.key,
                records: entry.value,
                resamples: resamples,
                random: random,
              ),
            )
            .toList()
          ..sort((left, right) => right.samples.compareTo(left.samples));
    return scores;
  }

  final byLeague = score('league', (record) => record.leagueName);
  final byLine = score(
    'line',
    (record) => record.pick == null
        ? null
        : '${record.pick!.line.toStringAsFixed(1)} 盤',
  );
  final byLeadTime = score('lead', (record) => _leadLabel(record));
  final positive = [
    ...byLeague,
    ...byLine,
    ...byLeadTime,
  ].where((group) => group.positive).toList();
  return GroupedEvaluation(
    samples: settled.length,
    byLeague: byLeague,
    byLine: byLine,
    byLeadTime: byLeadTime,
    message: positive.isEmpty
        ? '${settled.length} 場已結算前瞻中，沒有任何聯賽／盤口／時距子集的'
              '信賴區間完全高於零，即未有子集證明勝過盤口。'
        : '${settled.length} 場已結算前瞻中，'
              '${positive.map((group) => group.label).join('、')} '
              '的信賴區間完全高於零；區間會隨樣本增加而收窄，未必持續。',
  );
}

GroupScore _score({
  required String dimension,
  required String label,
  required List<ShadowForecast> records,
  required int resamples,
  required Random random,
}) {
  final gains = <double>[];
  var modelTotal = 0.0;
  var marketTotal = 0.0;
  for (final record in records) {
    final outcome = record.actualTotalCorners! > 9.5 ? 1.0 : 0.0;
    final model = pow(record.over9_5Probability! - outcome, 2).toDouble();
    final market = pow(record.marketOverProbability! - outcome, 2).toDouble();
    modelTotal += model;
    marketTotal += market;
    gains.add(market - model);
  }
  final count = records.length;
  final gain = gains.reduce((sum, value) => sum + value) / count;
  final interval = count < groupedEvaluationMinimumSamples
      ? const (low: 0.0, high: 0.0)
      : _bootstrapInterval(gains, resamples: resamples, random: random);
  return GroupScore(
    dimension: dimension,
    label: label,
    samples: count,
    modelBrier: modelTotal / count,
    marketBrier: marketTotal / count,
    gain: gain,
    gainLow: interval.low,
    gainHigh: interval.high,
  );
}

/// Percentile bootstrap of the mean of [gains].
({double low, double high}) _bootstrapInterval(
  List<double> gains, {
  required int resamples,
  required Random random,
}) {
  final means = <double>[];
  for (var draw = 0; draw < resamples; draw++) {
    var total = 0.0;
    for (var index = 0; index < gains.length; index++) {
      total += gains[random.nextInt(gains.length)];
    }
    means.add(total / gains.length);
  }
  means.sort();
  return (low: _percentile(means, 0.025), high: _percentile(means, 0.975));
}

double _percentile(List<double> sorted, double fraction) {
  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) {
    return sorted[lower];
  }
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

/// Which lead-time bucket a forecast was captured in.
String _leadLabel(ShadowForecast record) {
  final lead = record.matchDate.difference(record.capturedAt);
  if (lead.isNegative) {
    return '開賽後補寫';
  }
  if (lead < const Duration(hours: 2)) {
    return '開賽前 2 小時內';
  }
  if (lead < const Duration(hours: 6)) {
    return '開賽前 2–6 小時';
  }
  if (lead < const Duration(hours: 24)) {
    return '開賽前 6–24 小時';
  }
  return '開賽前逾 24 小時';
}
