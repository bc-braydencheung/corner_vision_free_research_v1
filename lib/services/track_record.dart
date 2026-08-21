/// Public ledger of every corner recommendation the app has ever shown.
///
/// Nothing here is derived from a claim: an entry exists only when a stored
/// shadow forecast can be paired with the quote history that was on screen at
/// the moment the forecast was captured, so a reader can check the taken quote,
/// the closing quote and the settled result against the record instead of
/// trusting a summary. Prediction quality (Brier against the market) and price
/// quality (closing-line value) are reported separately, because a model can
/// beat the market on price while losing on probability and the two must never
/// be blended into one flattering number.
///
/// Units are research units of one stake. They are not money: the app places no
/// bets and holds no account.
library;

import 'dart:math';

import '../models/football_mobile.dart';
import '../models/shadow_forecast.dart';
import 'market_timeline.dart';

/// Why a stored forecast could not enter the ledger.
enum TrackRecordSkip {
  /// No stored quote history for the fixture and line.
  noTimeline,

  /// No quote captured at or before the forecast, so no taken price exists.
  noTakenQuote,

  /// The stored quote pair cannot be turned into a probability.
  unusableOdds,
}

/// One graded fixture: what was shown, at what price, and what happened.
class TrackRecordEntry {
  const TrackRecordEntry({
    required this.matchId,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.line,
    required this.matchDate,
    required this.capturedAt,
    required this.direction,
    required this.modelProbability,
    required this.marketProbability,
    required this.takenOdds,
    required this.takenAt,
    required this.edge,
    required this.recommended,
    this.closingOdds,
    this.closingProbability,
    this.actualTotalCorners,
  });

  final String matchId;
  final String leagueName;
  final String homeTeam;
  final String awayTeam;
  final double line;
  final DateTime matchDate;

  /// When the forecast that produced this entry was captured.
  final DateTime capturedAt;

  /// `high` or `low`: the side the model leaned to at [takenOdds].
  final String direction;

  /// Model probability of the side taken, as shown at capture time.
  final double modelProbability;

  /// Margin-free market probability of the same side at capture time.
  final double marketProbability;
  final double takenOdds;

  /// Capture time of the quote used as the taken price.
  final DateTime takenAt;

  /// Expected value per unit stake at [takenOdds].
  final double edge;

  /// Whether the side cleared the recommendation threshold when shown.
  final bool recommended;

  /// Last quote of the side before kick-off, absent until kick-off passes.
  final double? closingOdds;

  /// Margin-free market probability implied by the closing quote.
  final double? closingProbability;
  final int? actualTotalCorners;

  String get directionLabel => direction == 'high' ? '大' : '細';

  bool get settled => actualTotalCorners != null;

  /// Whether the side taken was the winning side, `null` until settled.
  bool? get won {
    final actual = actualTotalCorners;
    if (actual == null) {
      return null;
    }
    final over = actual > line;
    return direction == 'high' ? over : !over;
  }

  /// Closing-line value: how much better the taken price was than the close.
  double? get closingLineValue {
    final close = closingOdds;
    if (close == null || close <= 1) {
      return null;
    }
    return takenOdds / close - 1;
  }

  /// Profit in research units of one stake, `null` until settled.
  double? get profitUnits {
    final result = won;
    if (result == null) {
      return null;
    }
    return result ? takenOdds - 1 : -1;
  }

  /// Squared error of the model probability against the settled outcome.
  double? get brierContribution => _squaredError(modelProbability);

  /// Same measure for the market, so the comparison uses one scale.
  double? get marketBrierContribution => _squaredError(marketProbability);

  double? _squaredError(double probability) {
    final result = won;
    if (result == null) {
      return null;
    }
    final target = result ? 1.0 : 0.0;
    final error = probability.clamp(0.0, 1.0) - target;
    return error * error;
  }
}

/// Ledger summary; every rate is over the entries that actually carry it.
class TrackRecordReport {
  const TrackRecordReport({
    required this.entries,
    required this.skipped,
    required this.recommended,
    required this.settled,
    required this.hits,
    required this.brier,
    required this.marketBrier,
    required this.brierSamples,
    required this.meanClosingLineValue,
    required this.beatClosingRate,
    required this.clvSamples,
    required this.netUnits,
    required this.maximumDrawdownUnits,
  });

  static const empty = TrackRecordReport(
    entries: [],
    skipped: <TrackRecordSkip, int>{},
    recommended: 0,
    settled: 0,
    hits: 0,
    brier: 0,
    marketBrier: 0,
    brierSamples: 0,
    meanClosingLineValue: 0,
    beatClosingRate: 0,
    clvSamples: 0,
    netUnits: 0,
    maximumDrawdownUnits: 0,
  );

  /// Newest first, so the page shows the latest fixtures without re-sorting.
  final List<TrackRecordEntry> entries;
  final Map<TrackRecordSkip, int> skipped;

  /// Entries that cleared the recommendation threshold when shown.
  final int recommended;

  /// Recommended entries whose result is known.
  final int settled;
  final int hits;

  /// Brier score of the recommended side over [brierSamples] settled entries.
  final double brier;
  final double marketBrier;
  final int brierSamples;
  final double meanClosingLineValue;
  final double beatClosingRate;
  final int clvSamples;

  /// Net research units at one unit per recommendation; never money.
  final double netUnits;

  /// Deepest peak-to-trough fall of the same unit curve.
  final double maximumDrawdownUnits;

  double get hitRate => settled == 0 ? 0 : hits / settled;

  bool get hasSettled => settled > 0;

  /// Whether the model's probabilities beat the market's on the same fixtures.
  ///
  /// Deliberately separate from [beatsClosing]: this is prediction quality.
  bool get beatsMarketBrier => brierSamples >= 20 && brier < marketBrier;

  /// Whether the prices taken were better than the closing prices.
  bool get beatsClosing => clvSamples >= 20 && meanClosingLineValue > 0;

  String get verdict {
    if (recommended == 0) {
      return '至今未出過推介，故無紀錄可公開。';
    }
    if (!hasSettled) {
      return '已出 $recommended 個推介，尚未有已結算賽果。';
    }
    if (brierSamples < 20) {
      return '已結算 $settled 個推介，樣本不足 20，未足以評估技巧。';
    }
    return beatsMarketBrier
        ? '已結算 $settled 個推介，Brier 勝過同場盤口。'
        : '已結算 $settled 個推介，Brier 未勝過同場盤口。';
  }
}

/// Builds the public ledger from stored forecasts and stored quote history.
///
/// [asOf] decides which fixtures have a final closing quote; a fixture that has
/// not kicked off keeps its closing fields empty rather than borrowing the
/// latest quote, because that quote can still move.
TrackRecordReport buildTrackRecord({
  required List<ShadowForecast> forecasts,
  required List<FootballOddsSnapshot> stored,
  required DateTime asOf,
  double line = 9.5,
  double minimumEdge = 0.02,
}) {
  final timelines = cornerTimelines(stored);
  final entries = <TrackRecordEntry>[];
  final skipped = <TrackRecordSkip, int>{};
  void refuse(TrackRecordSkip reason) =>
      skipped[reason] = (skipped[reason] ?? 0) + 1;

  for (final forecast in forecasts) {
    final timeline = timelines[forecast.matchId]
        ?.where((entry) => (entry.line - line).abs() < 0.01)
        .firstOrNull;
    if (timeline == null) {
      refuse(TrackRecordSkip.noTimeline);
      continue;
    }
    final taken = timeline.observations
        .where(
          (snapshot) =>
              !snapshot.inPlay &&
              !snapshot.capturedAt.toUtc().isAfter(forecast.capturedAt.toUtc()),
        )
        .lastOrNull;
    if (taken == null) {
      refuse(TrackRecordSkip.noTakenQuote);
      continue;
    }
    if (!_usable(taken)) {
      refuse(TrackRecordSkip.unusableOdds);
      continue;
    }
    final fair = twoWayFairProbabilities(taken.overOdds, taken.underOdds);
    if (fair == null) {
      refuse(TrackRecordSkip.unusableOdds);
      continue;
    }
    final overEdge = forecast.over9_5Probability * taken.overOdds - 1;
    final underEdge = (1 - forecast.over9_5Probability) * taken.underOdds - 1;
    final high = overEdge >= underEdge;
    final edge = high ? overEdge : underEdge;
    final kickOff = forecast.matchDate.toUtc();
    final closing = asOf.toUtc().isAfter(kickOff)
        ? timeline.closing(kickOff)
        : null;
    final closingUsable = closing != null && _usable(closing);
    final closingFair = closingUsable
        ? twoWayFairProbabilities(closing.overOdds, closing.underOdds)
        : null;
    entries.add(
      TrackRecordEntry(
        matchId: forecast.matchId,
        leagueName: forecast.leagueName,
        homeTeam: forecast.homeTeam,
        awayTeam: forecast.awayTeam,
        line: line,
        matchDate: forecast.matchDate,
        capturedAt: forecast.capturedAt,
        direction: high ? 'high' : 'low',
        modelProbability: high
            ? forecast.over9_5Probability
            : 1 - forecast.over9_5Probability,
        marketProbability: high ? fair.over : fair.under,
        takenOdds: high ? taken.overOdds : taken.underOdds,
        takenAt: taken.capturedAt,
        edge: edge,
        recommended: edge >= minimumEdge,
        closingOdds: closingUsable && closingFair != null
            ? (high ? closing.overOdds : closing.underOdds)
            : null,
        closingProbability: closingFair == null
            ? null
            : (high ? closingFair.over : closingFair.under),
        actualTotalCorners: forecast.actualTotalCorners,
      ),
    );
  }

  entries.sort((left, right) => right.matchDate.compareTo(left.matchDate));
  return _summarise(entries, skipped);
}

TrackRecordReport _summarise(
  List<TrackRecordEntry> entries,
  Map<TrackRecordSkip, int> skipped,
) {
  final recommended = entries.where((entry) => entry.recommended).toList();
  if (recommended.isEmpty) {
    return TrackRecordReport(
      entries: entries,
      skipped: skipped,
      recommended: 0,
      settled: 0,
      hits: 0,
      brier: 0,
      marketBrier: 0,
      brierSamples: 0,
      meanClosingLineValue: 0,
      beatClosingRate: 0,
      clvSamples: 0,
      netUnits: 0,
      maximumDrawdownUnits: 0,
    );
  }
  var settled = 0;
  var hits = 0;
  var brier = 0.0;
  var marketBrier = 0.0;
  var brierSamples = 0;
  var clv = 0.0;
  var beatClosing = 0;
  var clvSamples = 0;
  for (final entry in recommended) {
    if (entry.won == true) {
      hits++;
    }
    if (entry.settled) {
      settled++;
    }
    final error = entry.brierContribution;
    final marketError = entry.marketBrierContribution;
    if (error != null && marketError != null) {
      brier += error;
      marketBrier += marketError;
      brierSamples++;
    }
    final value = entry.closingLineValue;
    if (value != null) {
      clv += value;
      if (value > 0) {
        beatClosing++;
      }
      clvSamples++;
    }
  }

  // The unit curve runs in fixture order: a drawdown only means anything when
  // the losses are placed where they actually happened.
  final chronological = recommended.reversed
      .where((entry) => entry.settled)
      .toList();
  var running = 0.0;
  var peak = 0.0;
  var drawdown = 0.0;
  for (final entry in chronological) {
    running += entry.profitUnits ?? 0;
    peak = max(peak, running);
    drawdown = max(drawdown, peak - running);
  }

  return TrackRecordReport(
    entries: entries,
    skipped: skipped,
    recommended: recommended.length,
    settled: settled,
    hits: hits,
    brier: brierSamples == 0 ? 0 : brier / brierSamples,
    marketBrier: brierSamples == 0 ? 0 : marketBrier / brierSamples,
    brierSamples: brierSamples,
    meanClosingLineValue: clvSamples == 0 ? 0 : clv / clvSamples,
    beatClosingRate: clvSamples == 0 ? 0 : beatClosing / clvSamples,
    clvSamples: clvSamples,
    netUnits: running,
    maximumDrawdownUnits: drawdown,
  );
}

bool _usable(FootballOddsSnapshot snapshot) =>
    snapshot.overOdds.isFinite &&
    snapshot.underOdds.isFinite &&
    snapshot.overOdds > 1 &&
    snapshot.underOdds > 1;
