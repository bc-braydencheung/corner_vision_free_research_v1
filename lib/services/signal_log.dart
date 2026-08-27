/// Append-only log of how each fixture's shown signal moved over time.
///
/// A fixture card is recomputed from scratch on every refresh, so a fixture can
/// be a recommendation at one reading and 不建議 at the next. Only a series can
/// say which input moved: the HKJC price, the quoted line, or the model's own
/// probability. Every reading is written as it was shown — nothing is
/// recomputed later — and a reading is only appended when it differs from the
/// previous one by more than display noise, so an idle refresh adds nothing.
library;

import '../models/football_mobile.dart';
import '../models/hkjc_football.dart';
import '../models/signal_change.dart';
import '../models/team_news.dart';
import 'calibration_service.dart';
import 'corner_strength_service.dart';
import 'hkjc_corner_model.dart';
import 'hkjc_football_service.dart';
import 'market_anchor.dart';
import 'market_residual.dart';
import 'online_learning.dart';
import 'two_stage_corner_model.dart';

/// Readings kept per fixture: the first one, plus the most recent ones.
const signalLogPerMatchLimit = 20;

/// Fixtures older than this are dropped, so the log cannot grow without bound.
const signalLogRetention = Duration(days: 45);

/// Smallest move worth recording, in decimal odds.
const _oddsEpsilon = 0.005;

/// Smallest move worth recording, in probability and expected value.
const _probabilityEpsilon = 0.0025;

/// [existing] with a reading appended for every fixture whose shown signal
/// moved, and stale fixtures dropped.
///
/// The model is asked exactly as the fixture cards ask it, [suspended]
/// included, because this records what was shown rather than a second opinion.
List<SignalChange> updateSignalLog({
  required List<SignalChange> existing,
  required HkjcFootballSnapshot? snapshot,
  required Map<String, String> leagueNames,
  required DateTime asOf,
  MarketCalibration? calibration,
  CornerPriorTables priors = CornerPriorTables.empty,
  Map<String, FootballWeatherSnapshot> weather = const {},
  Map<String, TeamNewsSnapshot> teamNews = const {},
  OnlineLearningState? online,
  MarketAnchorState? anchor,
  MarketResidualState? residual,
  bool suspended = false,
  double minimumEdge = 0.02,
}) {
  final now = asOf.toUtc();
  final log =
      existing
          .where(
            (change) =>
                now.difference(change.matchDate.toUtc()) <= signalLogRetention,
          )
          .toList()
        ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  final current = snapshot;
  if (current == null) {
    return log;
  }
  final latest = <String, SignalChange>{};
  for (final change in log) {
    latest[change.matchId] = change;
  }
  final appended = <SignalChange>[];
  for (final code in hkjcFootballProfiles.keys) {
    final strengths = priors.strengths[code];
    final shots = priors.shots[code];
    final joint = priors.joint[code];
    for (final fixture in current.forLeague(code)) {
      // A started fixture's quote is no longer takeable, so a reading of it
      // would not be a signal the reader could have acted on.
      if (fixture.startedBy(asOf)) {
        continue;
      }
      final home = fixture.homeTeamEnglish.isEmpty
          ? fixture.homeTeam
          : fixture.homeTeamEnglish;
      final away = fixture.awayTeamEnglish.isEmpty
          ? fixture.awayTeam
          : fixture.awayTeamEnglish;
      final assessment = HkjcCornerModel(
        minimumEdge: minimumEdge,
        calibration: calibration,
        prior: combineCornerPriors(
          strengths?.priorFor(
            homeTeam: home,
            awayTeam: away,
            kickOff: fixture.kickOffTime,
          ),
          shots?.priorFor(
            homeTeam: home,
            awayTeam: away,
            kickOff: fixture.kickOffTime,
          ),
        ),
        weather: weather[fixture.matchId],
        online: online,
        anchor: anchor,
        residual: residual,
        joint: joint,
        homeNews: teamNews[fixture.homeTeam],
        awayNews: teamNews[fixture.awayTeam],
        suspended: suspended,
      ).assess(fixture);
      if (assessment == null) {
        continue;
      }
      final shown = assessment.recommendation ?? assessment.observation;
      if (shown == null) {
        continue;
      }
      final high = shown.direction == 'high';
      final reading = SignalChange(
        matchId: fixture.matchId,
        leagueCode: code,
        leagueName: leagueNames[code] ?? code,
        homeTeam: fixture.homeTeam,
        awayTeam: fixture.awayTeam,
        matchDate: fixture.kickOffTime,
        capturedAt: asOf,
        line: shown.line.line.line,
        direction: shown.direction,
        odds: shown.odds,
        modelProbability: high
            ? shown.line.modelHighProbability
            : shown.line.modelLowProbability,
        marketProbability: high
            ? shown.line.marketHighProbability
            : shown.line.marketLowProbability,
        edge: shown.edge,
        requiredEdge: assessment.signalGap?.requiredEdge ?? minimumEdge,
        recommended: assessment.recommendation != null,
      );
      if (!_moved(latest[fixture.matchId], reading)) {
        continue;
      }
      appended.add(reading);
    }
  }
  return _trimmed([...log, ...appended]);
}

/// Whether [reading] says something [previous] did not already say.
bool _moved(SignalChange? previous, SignalChange reading) {
  if (previous == null) {
    return true;
  }
  return previous.recommended != reading.recommended ||
      previous.direction != reading.direction ||
      (previous.line - reading.line).abs() >= 0.01 ||
      (previous.odds - reading.odds).abs() >= _oddsEpsilon ||
      (previous.modelProbability - reading.modelProbability).abs() >=
          _probabilityEpsilon ||
      (previous.edge - reading.edge).abs() >= _probabilityEpsilon;
}

/// Every fixture's readings, oldest first, keyed by HKJC match id.
Map<String, List<SignalChange>> signalLogByMatch(List<SignalChange> log) {
  final grouped = <String, List<SignalChange>>{};
  for (final change in log) {
    grouped.putIfAbsent(change.matchId, () => []).add(change);
  }
  for (final entries in grouped.values) {
    entries.sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
  }
  return grouped;
}

/// Caps each fixture at [signalLogPerMatchLimit] readings.
///
/// The first reading is always kept: it is the state the fixture was first
/// shown in, which is what a later change is read against.
List<SignalChange> _trimmed(List<SignalChange> log) {
  final grouped = signalLogByMatch(log);
  final kept = <SignalChange>[];
  for (final entries in grouped.values) {
    if (entries.length <= signalLogPerMatchLimit) {
      kept.addAll(entries);
      continue;
    }
    kept.add(entries.first);
    kept.addAll(entries.sublist(entries.length - (signalLogPerMatchLimit - 1)));
  }
  return kept
    ..sort((left, right) => left.capturedAt.compareTo(right.capturedAt));
}
