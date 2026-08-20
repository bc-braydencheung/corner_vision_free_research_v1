/// Turns the stored HKJC corner odds history into closing-line learning
/// observations.
///
/// Grading a forecast against the result needs the match to be over and gives
/// one coin-flip-like bit per match. Grading it against the closing line — the
/// last margin-free market probability before kick-off — needs only the stored
/// quote history, arrives at kick-off instead of after settlement, and lands on
/// a probability scale instead of on `0`/`1`, so the same number of fixtures
/// carries far more usable signal.
///
/// Everything here is deliberately refusing more than it accepts: a forecast is
/// only graded when the closing quote was captured strictly after the forecast
/// was made (otherwise the label is information the model already had), when
/// the line actually moved (an unmoved line grades every member identically)
/// and when kick-off has passed (so the closing quote can no longer change).
library;

import '../models/football_mobile.dart';
import '../models/shadow_forecast.dart';
import 'market_timeline.dart';
import 'online_learning.dart';

/// Why a forecast could not be graded against a closing line.
enum ClosingLineSkip {
  noTimeline,
  noClosingQuote,
  kickOffPending,
  closingNotAfterForecast,
  lineNeverMoved,
  unusableOdds,
}

/// Closing-line observations plus the reason every refused forecast was
/// refused, so the research page can show why a sample count is low instead of
/// silently reporting fewer samples.
class ClosingLineLearningSet {
  const ClosingLineLearningSet({
    required this.observations,
    required this.skipped,
  });

  static const empty = ClosingLineLearningSet(
    observations: [],
    skipped: <ClosingLineSkip, int>{},
  );

  final List<OnlineObservation> observations;
  final Map<ClosingLineSkip, int> skipped;

  int get graded => observations.length;

  int get considered =>
      graded + skipped.values.fold<int>(0, (total, count) => total + count);
}

/// Builds closing-line observations for the `over [line]` corner market.
///
/// [asOf] is the current time; a forecast whose kick-off has not passed is left
/// out because its closing quote is not yet final.
ClosingLineLearningSet closingLineLearningSet({
  required List<ShadowForecast> forecasts,
  required List<FootballOddsSnapshot> stored,
  required DateTime asOf,
  double line = 9.5,
}) {
  final timelines = cornerTimelines(stored);
  final observations = <OnlineObservation>[];
  final skipped = <ClosingLineSkip, int>{};
  void refuse(ClosingLineSkip reason) =>
      skipped[reason] = (skipped[reason] ?? 0) + 1;

  for (final forecast in forecasts) {
    final kickOff = forecast.matchDate.toUtc();
    if (!asOf.toUtc().isAfter(kickOff)) {
      refuse(ClosingLineSkip.kickOffPending);
      continue;
    }
    final timeline = timelines[forecast.matchId]
        ?.where((entry) => (entry.line - line).abs() < 0.01)
        .firstOrNull;
    if (timeline == null) {
      refuse(ClosingLineSkip.noTimeline);
      continue;
    }
    final close = timeline.closing(kickOff);
    final open = timeline.opening;
    if (close == null || open == null) {
      refuse(ClosingLineSkip.noClosingQuote);
      continue;
    }
    if (close.capturedAt.toUtc() == open.capturedAt.toUtc()) {
      refuse(ClosingLineSkip.lineNeverMoved);
      continue;
    }
    if (!close.capturedAt.toUtc().isAfter(forecast.capturedAt.toUtc())) {
      refuse(ClosingLineSkip.closingNotAfterForecast);
      continue;
    }
    if (!_usable(close) || !_usable(open)) {
      refuse(ClosingLineSkip.unusableOdds);
      continue;
    }
    final closingFair = twoWayFairProbabilities(
      close.overOdds,
      close.underOdds,
    ).over;
    final openingFair = twoWayFairProbabilities(
      open.overOdds,
      open.underOdds,
    ).over;
    observations.add(
      OnlineObservation.closingLine(
        settledAt: kickOff,
        target: closingFair,
        predictions: {
          'model': forecast.over9_5Probability,
          // The price the model was looking at is the baseline it has to beat:
          // reproducing the opening line is not skill.
          'fallback': forecast.marketOverProbability ?? openingFair,
        },
        marketShift: closingFair - openingFair,
      ),
    );
  }
  return ClosingLineLearningSet(observations: observations, skipped: skipped);
}

bool _usable(FootballOddsSnapshot snapshot) =>
    snapshot.overOdds.isFinite &&
    snapshot.underOdds.isFinite &&
    snapshot.overOdds > 1 &&
    snapshot.underOdds > 1;
