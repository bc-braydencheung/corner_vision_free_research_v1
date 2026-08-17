import 'dart:math';

import '../models/football_mobile.dart';
import 'count_distribution.dart';

/// Time-varying corner strength of one team.
///
/// [attack] and [defence] are log multipliers on the league venue baseline, so
/// an expected count is `leagueBaseline * exp(attack + opponentDefence)`. The
/// variances are the Kalman posterior variances of those two states and are
/// what makes a young or long-idle team automatically count for less when the
/// prior is blended against the market.
class TeamCornerStrength {
  const TeamCornerStrength({
    required this.team,
    required this.attack,
    required this.defence,
    required this.attackVariance,
    required this.defenceVariance,
    required this.matches,
    required this.lastPlayed,
  });

  final String team;
  final double attack;
  final double defence;
  final double attackVariance;
  final double defenceVariance;
  final double matches;
  final DateTime? lastPlayed;
}

/// Model-side corner expectation for one fixture, before the market is seen.
class CornerMeanPrior {
  const CornerMeanPrior({
    required this.homeMean,
    required this.awayMean,
    required this.logVariance,
    required this.dispersion,
    required this.teamMatches,
  });

  final double homeMean;
  final double awayMean;

  /// Posterior variance of `log(totalMean)`; drives the market blend weight.
  final double logVariance;

  /// NB2 dispersion measured on this league's own out-of-sample residuals.
  final double dispersion;

  /// Weighted match count of the *less* observed of the two teams.
  final double teamMatches;

  double get totalMean => homeMean + awayMean;

  /// A prior resting on a handful of matches must not push the market around.
  bool get reliable => teamMatches >= 6 && logVariance < 0.05;
}

/// Fitted league table of corner strengths plus the league's own dispersion.
class CornerStrengthTable {
  const CornerStrengthTable({
    required this.leagueCode,
    required this.teams,
    required this.leagueHomeMean,
    required this.leagueAwayMean,
    required this.dispersion,
    required this.matches,
    required this.trainedThrough,
  });

  static const empty = CornerStrengthTable(
    leagueCode: '',
    teams: {},
    leagueHomeMean: 5.5,
    leagueAwayMean: 4.8,
    dispersion: 0,
    matches: 0,
    trainedThrough: null,
  );

  final String leagueCode;

  /// Keyed by [normaliseTeamName].
  final Map<String, TeamCornerStrength> teams;
  final double leagueHomeMean;
  final double leagueAwayMean;
  final double dispersion;
  final int matches;
  final DateTime? trainedThrough;

  /// Looks a team up by any spelling, falling back to token overlap so the
  /// HKJC English names ("Man City") reach the football-data ones ("Man City").
  TeamCornerStrength? resolve(String name) {
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
    TeamCornerStrength? best;
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

  /// Prior corner means for a fixture, or `null` when either side is unknown.
  CornerMeanPrior? priorFor({
    required String homeTeam,
    required String awayTeam,
    DateTime? kickOff,
  }) {
    final home = resolve(homeTeam);
    final away = resolve(awayTeam);
    if (home == null || away == null) {
      return null;
    }
    final decayedHome = _decay(home, kickOff);
    final decayedAway = _decay(away, kickOff);
    final homeMean =
        leagueHomeMean * exp(decayedHome.attack + decayedAway.defence);
    final awayMean =
        leagueAwayMean * exp(decayedAway.attack + decayedHome.defence);
    final total = homeMean + awayMean;
    final homeShare = homeMean / max(total, 1e-6);
    final awayShare = awayMean / max(total, 1e-6);
    // Variance of a share-weighted sum of the four independent log states.
    final logVariance =
        homeShare *
            homeShare *
            (decayedHome.attackVariance + decayedAway.defenceVariance) +
        awayShare *
            awayShare *
            (decayedAway.attackVariance + decayedHome.defenceVariance);
    return CornerMeanPrior(
      homeMean: homeMean,
      awayMean: awayMean,
      logVariance: logVariance,
      dispersion: dispersion,
      teamMatches: min(home.matches, away.matches),
    );
  }

  /// Ornstein-Uhlenbeck decay of a stale state towards the league average.
  TeamCornerStrength _decay(TeamCornerStrength state, DateTime? at) {
    final last = state.lastPlayed;
    if (at == null || last == null || !at.isAfter(last)) {
      return state;
    }
    final days = at.difference(last).inDays.clamp(0, 400).toDouble();
    final rho = exp(-days / CornerStrengthModel.reversionDays);
    final drift = (1 - rho * rho) * CornerStrengthModel.priorVariance;
    return TeamCornerStrength(
      team: state.team,
      attack: state.attack * rho,
      defence: state.defence * rho,
      attackVariance: rho * rho * state.attackVariance + drift,
      defenceVariance: rho * rho * state.defenceVariance + drift,
      matches: state.matches,
      lastPlayed: last,
    );
  }
}

/// Hierarchical, time-varying corner strength fit.
///
/// Every completed match is one Kalman step on the four log states it touches
/// (both attacks, both defences). Between matches the states revert towards
/// the league mean, which is the hierarchical prior: a team never wanders far
/// from average on thin evidence, and a team that stops playing loses its edge
/// gradually instead of keeping a stale rating forever. Support-division
/// matches enter with a lower weight, mirroring the rest of the app.
class CornerStrengthModel {
  const CornerStrengthModel();

  /// Prior (and stationary) variance of each log state.
  static const priorVariance = 0.03;

  /// Time constant of the reversion towards the league mean.
  static const reversionDays = 260.0;

  /// Weight applied to matches from the support division.
  static const supportWeight = 0.55;

  CornerStrengthTable fit(
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
                  (row.division == league.code ||
                      row.division == league.supportCode),
            )
            .toList()
          ..sort((left, right) {
            final date = left.date.compareTo(right.date);
            return date != 0 ? date : left.matchId.compareTo(right.matchId);
          });
    if (relevant.isEmpty) {
      return CornerStrengthTable.empty;
    }
    final states = <String, _MutableStrength>{};
    var leagueHome = 5.5;
    var leagueAway = 4.8;
    var leagueWeight = 4.0;
    final observedTotals = <double>[];
    final predictedTotals = <double>[];
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
        () => _MutableStrength(row.homeTeam),
      );
      final away = states.putIfAbsent(
        normaliseTeamName(row.awayTeam),
        () => _MutableStrength(row.awayTeam),
      );
      home.revertTo(date);
      away.revertTo(date);

      final expectedHome = leagueHome * exp(home.attack + away.defence);
      final expectedAway = leagueAway * exp(away.attack + home.defence);
      final actualHome = row.homeCorners!.toDouble();
      final actualAway = row.awayCorners!.toDouble();
      if (primary) {
        observedTotals.add(actualHome + actualAway);
        predictedTotals.add(expectedHome + expectedAway);
        leagueHome =
            (leagueHome * leagueWeight + actualHome) / (leagueWeight + 1);
        leagueAway =
            (leagueAway * leagueWeight + actualAway) / (leagueWeight + 1);
        leagueWeight = min(leagueWeight + 1, 300);
        matches++;
        trainedThrough = date;
      }

      _kalmanStep(
        attacker: home,
        defender: away,
        expected: expectedHome,
        actual: actualHome,
        weight: weight,
      );
      _kalmanStep(
        attacker: away,
        defender: home,
        expected: expectedAway,
        actual: actualAway,
        weight: weight,
      );
      home.lastPlayed = date;
      away.lastPlayed = date;
      home.matches += weight;
      away.matches += weight;
    }

    return CornerStrengthTable(
      leagueCode: league.code,
      teams: {
        for (final entry in states.entries) entry.key: entry.value.snapshot(),
      },
      leagueHomeMean: leagueHome,
      leagueAwayMean: leagueAway,
      dispersion: estimateDispersion(observedTotals, predictedTotals),
      matches: matches,
      trainedThrough: trainedThrough,
    );
  }

  /// One extended-Kalman update in log space.
  ///
  /// The innovation `log((y + 0.5) / (mu + 0.5))` is shared between the
  /// attacking and the defending state in proportion to their uncertainty, so
  /// whichever state is currently less certain absorbs more of the surprise.
  static void _kalmanStep({
    required _MutableStrength attacker,
    required _MutableStrength defender,
    required double expected,
    required double actual,
    required double weight,
  }) {
    final innovation = log((actual + 0.5) / (max(expected, 0.2) + 0.5));
    // Poisson noise in log space; a low-count match carries little signal.
    final observationVariance = 1 / max(expected, 0.5) / max(weight, 1e-3);
    final total =
        attacker.attackVariance +
        defender.defenceVariance +
        observationVariance;
    final attackGain = attacker.attackVariance / total;
    final defenceGain = defender.defenceVariance / total;
    attacker.attack += attackGain * innovation;
    defender.defence += defenceGain * innovation;
    attacker.attackVariance *= 1 - attackGain;
    defender.defenceVariance *= 1 - defenceGain;
  }
}

class _MutableStrength {
  _MutableStrength(this.team);

  final String team;
  double attack = 0;
  double defence = 0;
  double attackVariance = CornerStrengthModel.priorVariance;
  double defenceVariance = CornerStrengthModel.priorVariance;
  double matches = 0;
  DateTime? lastPlayed;

  void revertTo(DateTime date) {
    final last = lastPlayed;
    if (last == null || !date.isAfter(last)) {
      return;
    }
    final days = date.difference(last).inDays.clamp(0, 400).toDouble();
    final rho = exp(-days / CornerStrengthModel.reversionDays);
    final drift = (1 - rho * rho) * CornerStrengthModel.priorVariance;
    attack *= rho;
    defence *= rho;
    attackVariance = rho * rho * attackVariance + drift;
    defenceVariance = rho * rho * defenceVariance + drift;
  }

  TeamCornerStrength snapshot() => TeamCornerStrength(
    team: team,
    attack: attack,
    defence: defence,
    attackVariance: attackVariance,
    defenceVariance: defenceVariance,
    matches: matches,
    lastPlayed: lastPlayed,
  );
}

/// Canonical key for a club name across the free sources.
///
/// Lower-cases, strips accents and punctuation and drops the corporate suffixes
/// ("fc", "cf", "afc", "united"-style keepers excluded) that differ between
/// football-data.co.uk and the HKJC English spellings.
String normaliseTeamName(String name) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  const noise = {'fc', 'cf', 'afc', 'sc', 'ac', 'cd', 'sd', 'ud', 'club'};
  final lower = name.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final character = String.fromCharCode(rune);
    final mapped = accents[character] ?? character;
    if (RegExp(r'[a-z0-9 ]').hasMatch(mapped)) {
      buffer.write(mapped);
    } else {
      buffer.write(' ');
    }
  }
  final tokens = buffer
      .toString()
      .split(' ')
      .where((token) => token.isNotEmpty && !noise.contains(token))
      .toList();
  return tokens.join(' ');
}
