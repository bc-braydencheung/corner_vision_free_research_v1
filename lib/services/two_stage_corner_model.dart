import 'dart:math';

import '../models/football_mobile.dart';
import 'corner_strength_model.dart';
import 'count_distribution.dart';

/// Shot volume and shot-to-corner conversion of one team.
///
/// All three states are log multipliers on the league venue baseline, so an
/// expected shot count is `leagueShots * exp(shotAttack + opponentShotDefence)`
/// and an expected corner count is that number times
/// `leagueConversion * exp(conversion)`.
class TeamShotProfile {
  const TeamShotProfile({
    required this.team,
    required this.shotAttack,
    required this.shotDefence,
    required this.conversion,
    required this.matches,
    required this.lastPlayed,
  });

  final String team;
  final double shotAttack;
  final double shotDefence;

  /// Log multiplier on the league corners-per-shot rate.
  final double conversion;
  final double matches;
  final DateTime? lastPlayed;

  /// Shrinkage of a state towards zero on thin evidence.
  double get credibility => matches / (matches + TwoStageCornerModel.shrinkage);
}

/// Corner tendency of one referee, relative to the league.
class RefereeProfile {
  const RefereeProfile({
    required this.referee,
    required this.logFactor,
    required this.matches,
  });

  final String referee;

  /// Shrunk log multiplier on the league total-corner mean.
  final double logFactor;
  final int matches;

  bool get reliable => matches >= TwoStageCornerModel.minimumRefereeMatches;
}

/// League-level two-stage table: shots first, corners per shot second.
class ShotCornerTable {
  const ShotCornerTable({
    required this.leagueCode,
    required this.teams,
    required this.referees,
    required this.leagueHomeShots,
    required this.leagueAwayShots,
    required this.leagueHomeConversion,
    required this.leagueAwayConversion,
    required this.dispersion,
    required this.matches,
    required this.trainedThrough,
  });

  static const empty = ShotCornerTable(
    leagueCode: '',
    teams: {},
    referees: {},
    leagueHomeShots: 13.5,
    leagueAwayShots: 11.5,
    leagueHomeConversion: 0.41,
    leagueAwayConversion: 0.42,
    dispersion: 0,
    matches: 0,
    trainedThrough: null,
  );

  final String leagueCode;

  /// Keyed by [normaliseTeamName].
  final Map<String, TeamShotProfile> teams;

  /// Keyed by [normaliseRefereeName].
  final Map<String, RefereeProfile> referees;
  final double leagueHomeShots;
  final double leagueAwayShots;
  final double leagueHomeConversion;
  final double leagueAwayConversion;

  /// NB2 dispersion of the two-stage total against its own training residuals.
  final double dispersion;
  final int matches;
  final DateTime? trainedThrough;

  TeamShotProfile? resolve(String name) {
    final key = normaliseTeamName(name);
    if (key.isEmpty) {
      return null;
    }
    final direct = teams[key];
    if (direct != null) {
      return direct;
    }
    final wanted = key.split(' ').where((token) => token.length > 2).toSet();
    if (wanted.isEmpty) {
      return null;
    }
    TeamShotProfile? best;
    var bestScore = 0.0;
    for (final entry in teams.entries) {
      final candidate = entry.key
          .split(' ')
          .where((token) => token.length > 2)
          .toSet();
      if (candidate.isEmpty) {
        continue;
      }
      final shared = wanted.intersection(candidate).length;
      if (shared == 0) {
        continue;
      }
      final score = shared / max(wanted.length, candidate.length);
      if (score > bestScore) {
        bestScore = score;
        best = entry.value;
      }
    }
    return bestScore >= 0.5 ? best : null;
  }

  RefereeProfile? resolveReferee(String? name) {
    if (name == null) {
      return null;
    }
    final key = normaliseRefereeName(name);
    return key.isEmpty ? null : referees[key];
  }

  /// Two-stage prior for a fixture, or `null` when either team is unknown.
  ///
  /// The referee factor only enters when that official has enough matches in
  /// the free history; an unknown or rarely seen referee leaves the mean alone
  /// and widens nothing, which is the honest default.
  CornerMeanPrior? priorFor({
    required String homeTeam,
    required String awayTeam,
    String? referee,
    DateTime? kickOff,
  }) {
    final home = resolve(homeTeam);
    final away = resolve(awayTeam);
    if (home == null || away == null) {
      return null;
    }
    final decayHome = _decay(home, kickOff);
    final decayAway = _decay(away, kickOff);
    final officialProfile = resolveReferee(referee);
    final official = officialProfile != null && officialProfile.reliable
        ? exp(officialProfile.logFactor)
        : 1.0;

    final homeShots =
        leagueHomeShots * exp(decayHome.shotAttack + decayAway.shotDefence);
    final awayShots =
        leagueAwayShots * exp(decayAway.shotAttack + decayHome.shotDefence);
    final homeMean =
        homeShots * leagueHomeConversion * exp(decayHome.conversion) * official;
    final awayMean =
        awayShots * leagueAwayConversion * exp(decayAway.conversion) * official;

    // Each of the two stages contributes its own uncertainty, scaled down by
    // how much evidence the weaker of the two teams carries.
    final weakest = min(decayHome.matches, decayAway.matches);
    final credibility = weakest / (weakest + TwoStageCornerModel.shrinkage);
    final logVariance =
        (TwoStageCornerModel.shotLogVariance +
            TwoStageCornerModel.conversionLogVariance) *
        (1 - credibility * 0.85);
    return CornerMeanPrior(
      homeMean: homeMean,
      awayMean: awayMean,
      logVariance: logVariance,
      dispersion: dispersion,
      teamMatches: weakest,
    );
  }

  TeamShotProfile _decay(TeamShotProfile state, DateTime? at) {
    final last = state.lastPlayed;
    if (at == null || last == null || !at.isAfter(last)) {
      return state;
    }
    final days = at.difference(last).inDays.clamp(0, 400).toDouble();
    final rho = exp(-days / CornerStrengthModel.reversionDays);
    return TeamShotProfile(
      team: state.team,
      shotAttack: state.shotAttack * rho,
      shotDefence: state.shotDefence * rho,
      conversion: state.conversion * rho,
      matches: state.matches,
      lastPlayed: last,
    );
  }
}

/// Two-stage corner model: shot volume, then shot-to-corner conversion.
///
/// A corner is a *consequence* of a blocked or deflected attempt, so modelling
/// the count directly throws away the free shot columns of the football-data
/// history. Splitting the chain lets a team that shoots a lot from range (many
/// blocks, many corners) separate from a team with the same corner count driven
/// by a thin sample, and it makes the referee enter where it physically acts:
/// on how much of the play is allowed to continue rather than on corners as
/// such.
///
/// Everything is fitted with exponentially weighted log means, which is the
/// cheap deterministic counterpart of the Kalman fit used for the direct corner
/// strength model, and both priors are combined afterwards by
/// [combineCornerPriors] so the two views can disagree visibly.
class TwoStageCornerModel {
  const TwoStageCornerModel();

  /// Matches needed before a team state is trusted at ~50%.
  static const shrinkage = 8.0;

  /// Half-life of the exponential weighting, in matches.
  static const halfLifeMatches = 26.0;

  /// Prior log variance of the shot stage.
  static const shotLogVariance = 0.020;

  /// Prior log variance of the conversion stage.
  static const conversionLogVariance = 0.016;

  /// Matches before a referee factor is allowed to move the mean.
  static const minimumRefereeMatches = 12;

  /// Referee shrinkage weight, in matches.
  static const refereeShrinkage = 25.0;

  /// Weight applied to matches from the support division.
  static const supportWeight = CornerStrengthModel.supportWeight;

  ShotCornerTable fit(
    List<FootballMatchRecord> rows,
    FootballLeagueConfig league,
  ) {
    final relevant =
        rows
            .where(
              (row) =>
                  row.isComplete &&
                  row.homeCorners != null &&
                  row.awayCorners != null &&
                  (row.homeShots ?? 0) > 0 &&
                  (row.awayShots ?? 0) > 0 &&
                  (row.division == league.code ||
                      row.division == league.supportCode),
            )
            .toList()
          ..sort((left, right) {
            final date = left.date.compareTo(right.date);
            return date != 0 ? date : left.matchId.compareTo(right.matchId);
          });
    if (relevant.isEmpty) {
      return ShotCornerTable.empty;
    }

    final states = <String, _MutableShotProfile>{};
    final refereeTotals = <String, _MutableReferee>{};
    var leagueHomeShots = ShotCornerTable.empty.leagueHomeShots;
    var leagueAwayShots = ShotCornerTable.empty.leagueAwayShots;
    var leagueHomeCorners = 5.5;
    var leagueAwayCorners = 4.8;
    var leagueWeight = 4.0;
    final observed = <double>[];
    final predicted = <double>[];
    var matches = 0;
    DateTime? trainedThrough;

    for (final row in relevant) {
      final date = DateTime.tryParse(row.date);
      if (date == null) {
        continue;
      }
      final primary = row.division == league.code;
      final weight = primary ? 1.0 : supportWeight;
      final home = states.putIfAbsent(
        normaliseTeamName(row.homeTeam),
        () => _MutableShotProfile(row.homeTeam),
      );
      final away = states.putIfAbsent(
        normaliseTeamName(row.awayTeam),
        () => _MutableShotProfile(row.awayTeam),
      );

      final homeShots = row.homeShots!.toDouble();
      final awayShots = row.awayShots!.toDouble();
      final homeCorners = row.homeCorners!.toDouble();
      final awayCorners = row.awayCorners!.toDouble();
      final leagueHomeConversion =
          leagueHomeCorners / max(leagueHomeShots, 1e-3);
      final leagueAwayConversion =
          leagueAwayCorners / max(leagueAwayShots, 1e-3);

      if (primary) {
        final expectedHome =
            leagueHomeShots *
            exp(home.shotAttack + away.shotDefence) *
            leagueHomeConversion *
            exp(home.conversion);
        final expectedAway =
            leagueAwayShots *
            exp(away.shotAttack + home.shotDefence) *
            leagueAwayConversion *
            exp(away.conversion);
        observed.add(homeCorners + awayCorners);
        predicted.add(expectedHome + expectedAway);
        leagueHomeShots =
            (leagueHomeShots * leagueWeight + homeShots) / (leagueWeight + 1);
        leagueAwayShots =
            (leagueAwayShots * leagueWeight + awayShots) / (leagueWeight + 1);
        leagueHomeCorners =
            (leagueHomeCorners * leagueWeight + homeCorners) /
            (leagueWeight + 1);
        leagueAwayCorners =
            (leagueAwayCorners * leagueWeight + awayCorners) /
            (leagueWeight + 1);
        leagueWeight = min(leagueWeight + 1, 300);
        matches++;
        trainedThrough = date;

        final official = normaliseRefereeName(row.referee ?? '');
        if (official.isNotEmpty) {
          final tracker = refereeTotals.putIfAbsent(
            official,
            () => _MutableReferee(row.referee!),
          );
          tracker.observe(
            homeCorners + awayCorners,
            leagueHomeCorners + leagueAwayCorners,
          );
        }
      }

      home.observe(
        shotsFor: homeShots,
        shotsAgainst: awayShots,
        leagueShotsFor: leagueHomeShots,
        leagueShotsAgainst: leagueAwayShots,
        cornersFor: homeCorners,
        conversionBaseline: leagueHomeCorners / max(leagueHomeShots, 1e-3),
        opponentShotDefence: away.shotDefence,
        opponentShotAttack: away.shotAttack,
        weight: weight,
        date: date,
      );
      away.observe(
        shotsFor: awayShots,
        shotsAgainst: homeShots,
        leagueShotsFor: leagueAwayShots,
        leagueShotsAgainst: leagueHomeShots,
        cornersFor: awayCorners,
        conversionBaseline: leagueAwayCorners / max(leagueAwayShots, 1e-3),
        opponentShotDefence: home.shotDefence,
        opponentShotAttack: home.shotAttack,
        weight: weight,
        date: date,
      );
    }

    return ShotCornerTable(
      leagueCode: league.code,
      teams: {
        for (final entry in states.entries) entry.key: entry.value.snapshot(),
      },
      referees: {
        for (final entry in refereeTotals.entries)
          entry.key: entry.value.snapshot(),
      },
      leagueHomeShots: leagueHomeShots,
      leagueAwayShots: leagueAwayShots,
      leagueHomeConversion: leagueHomeCorners / max(leagueHomeShots, 1e-3),
      leagueAwayConversion: leagueAwayCorners / max(leagueAwayShots, 1e-3),
      dispersion: estimateDispersion(observed, predicted),
      matches: matches,
      trainedThrough: trainedThrough,
    );
  }
}

/// Inverse-variance blend of two corner priors in log space.
///
/// Returns whichever prior exists when only one does, and `null` when neither
/// does. The blended split keeps the home/away ratio of the more certain prior
/// so a two-stage view with a very different total does not silently rewrite
/// which side of the pitch the corners come from.
CornerMeanPrior? combineCornerPriors(
  CornerMeanPrior? first,
  CornerMeanPrior? second,
) {
  if (first == null || !first.reliable) {
    return second != null && second.reliable ? second : first ?? second;
  }
  if (second == null || !second.reliable) {
    return first;
  }
  final firstWeight = 1 / max(first.logVariance, 1e-6);
  final secondWeight = 1 / max(second.logVariance, 1e-6);
  final total = firstWeight + secondWeight;
  final logTotal =
      (firstWeight * log(max(first.totalMean, 1e-6)) +
          secondWeight * log(max(second.totalMean, 1e-6))) /
      total;
  final blendedTotal = exp(logTotal);
  final anchor = first.logVariance <= second.logVariance ? first : second;
  final homeShare = anchor.homeMean / max(anchor.totalMean, 1e-6);
  return CornerMeanPrior(
    homeMean: blendedTotal * homeShare,
    awayMean: blendedTotal * (1 - homeShare),
    logVariance: 1 / total,
    dispersion: max(first.dispersion, second.dispersion),
    teamMatches: max(first.teamMatches, second.teamMatches),
  );
}

/// Canonical key for a referee name across seasons and spellings.
String normaliseRefereeName(String name) {
  final buffer = StringBuffer();
  for (final rune in name.toLowerCase().runes) {
    final character = String.fromCharCode(rune);
    buffer.write(RegExp(r'[a-z ]').hasMatch(character) ? character : ' ');
  }
  return buffer
      .toString()
      .split(' ')
      .where((token) => token.isNotEmpty)
      .join(' ');
}

class _MutableShotProfile {
  _MutableShotProfile(this.team);

  static final double _decayPerMatch = pow(
    0.5,
    1 / TwoStageCornerModel.halfLifeMatches,
  ).toDouble();

  final String team;
  double shotAttack = 0;
  double shotDefence = 0;
  double conversion = 0;
  double matches = 0;
  DateTime? lastPlayed;

  void observe({
    required double shotsFor,
    required double shotsAgainst,
    required double leagueShotsFor,
    required double leagueShotsAgainst,
    required double cornersFor,
    required double conversionBaseline,
    required double opponentShotDefence,
    required double opponentShotAttack,
    required double weight,
    required DateTime date,
  }) {
    final gain = weight * (1 - _decayPerMatch);
    final attackTarget =
        log(max(shotsFor, 0.5) / max(leagueShotsFor, 0.5)) -
        opponentShotDefence;
    final defenceTarget =
        log(max(shotsAgainst, 0.5) / max(leagueShotsAgainst, 0.5)) -
        opponentShotAttack;
    final conversionTarget = log(
      (cornersFor + 0.5) / (max(shotsFor, 0.5) * conversionBaseline + 0.5),
    );
    shotAttack += gain * (attackTarget - shotAttack);
    shotDefence += gain * (defenceTarget - shotDefence);
    conversion += gain * (conversionTarget - conversion);
    matches += weight;
    lastPlayed = date;
  }

  TeamShotProfile snapshot() {
    final credibility = matches / (matches + TwoStageCornerModel.shrinkage);
    return TeamShotProfile(
      team: team,
      shotAttack: shotAttack * credibility,
      shotDefence: shotDefence * credibility,
      conversion: conversion * credibility,
      matches: matches,
      lastPlayed: lastPlayed,
    );
  }
}

class _MutableReferee {
  _MutableReferee(this.referee);

  final String referee;
  double logSum = 0;
  int matches = 0;

  void observe(double total, double leagueTotal) {
    logSum += log((total + 0.5) / (max(leagueTotal, 0.5) + 0.5));
    matches++;
  }

  RefereeProfile snapshot() {
    final shrunk =
        logSum / (matches + TwoStageCornerModel.refereeShrinkage).toDouble();
    return RefereeProfile(
      referee: referee,
      logFactor: shrunk,
      matches: matches,
    );
  }
}
