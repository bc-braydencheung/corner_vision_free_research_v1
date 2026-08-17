import 'dart:math';

import '../models/football_mobile.dart';

/// Measured joint behaviour of the two teams' corner counts in one league.
///
/// The rest of the app models the *total* directly, which silently assumes the
/// two counts are independent. They are not: a side that camps in the other
/// half takes the corners and concedes few, which pulls the pair towards
/// negative correlation, while an open end-to-end match pulls it positive. The
/// sign is an empirical question, so it is measured here on the free history
/// instead of assumed, and the only thing it is allowed to change is the width
/// of the total distribution — never its mean.
class BivariateCornerFit {
  const BivariateCornerFit({
    required this.leagueCode,
    required this.homeMean,
    required this.awayMean,
    required this.homeVariance,
    required this.awayVariance,
    required this.covariance,
    required this.matches,
    required this.trainedThrough,
  });

  static const empty = BivariateCornerFit(
    leagueCode: '',
    homeMean: 0,
    awayMean: 0,
    homeVariance: 0,
    awayVariance: 0,
    covariance: 0,
    matches: 0,
    trainedThrough: null,
  );

  /// Matches needed before the measured correlation is used at all.
  static const minimumMatches = 200;

  final String leagueCode;
  final double homeMean;
  final double awayMean;
  final double homeVariance;
  final double awayVariance;
  final double covariance;
  final int matches;
  final DateTime? trainedThrough;

  /// Pearson correlation of the home and away corner counts.
  double get correlation {
    final scale = sqrt(homeVariance * awayVariance);
    if (scale <= 1e-9) {
      return 0;
    }
    return (covariance / scale).clamp(-1.0, 1.0);
  }

  bool get reliable => matches >= minimumMatches && correlation.isFinite;

  double get totalMean => homeMean + awayMean;

  /// Variance of the total implied by the measured marginals and covariance.
  double get totalVariance => homeVariance + awayVariance + 2 * covariance;

  /// Variance the total would have if the two counts were independent Poisson
  /// counts, which is the assumption the single-total model makes.
  double get independentPoissonVariance => totalMean;

  /// NB2 dispersion that reproduces [totalVariance] at [mean].
  ///
  /// `Var(X) = mean * (1 + alpha * mean)`, so a joint distribution wider than
  /// Poisson maps to a positive dispersion and a narrower one maps to zero: the
  /// model is allowed to widen on measured evidence, never to sharpen itself
  /// below the count floor on it.
  double dispersionFor(double mean) {
    if (!reliable || mean <= 0 || !totalVariance.isFinite) {
      return 0;
    }
    final scaled = totalVariance * pow(mean / max(totalMean, 1e-6), 2);
    final excess = scaled - mean;
    if (excess <= 0) {
      return 0;
    }
    return (excess / (mean * mean)).clamp(0.0, 0.25);
  }

  /// Human readable note for the research pages.
  String get note {
    if (matches == 0) {
      return '未有已完成賽事，主客角球相關性未量度。';
    }
    if (!reliable) {
      return '只有 $matches 場已完成賽事（需 $minimumMatches 場），'
          '主客角球相關性未採用。';
    }
    final rho = correlation;
    final direction = rho < -0.02
        ? '負相關（一隊壓場另一隊少角球）'
        : rho > 0.02
        ? '正相關（對攻拉高雙方角球）'
        : '接近獨立';
    return '$matches 場量得 ρ=${rho.toStringAsFixed(3)}：$direction；'
        '總數變異 ${totalVariance.toStringAsFixed(2)}'
        '（獨立泊松假設為 ${independentPoissonVariance.toStringAsFixed(2)}）。';
  }
}

/// Fits [BivariateCornerFit] per league from the stored free history.
class BivariateCornerModel {
  const BivariateCornerModel();

  BivariateCornerFit fit(
    List<FootballMatchRecord> rows,
    FootballLeagueConfig league,
  ) {
    var count = 0;
    var homeSum = 0.0;
    var awaySum = 0.0;
    var homeSquares = 0.0;
    var awaySquares = 0.0;
    var products = 0.0;
    DateTime? trainedThrough;
    for (final row in rows) {
      if (row.division != league.code ||
          !row.isComplete ||
          row.homeCorners == null ||
          row.awayCorners == null) {
        continue;
      }
      final home = row.homeCorners!.toDouble();
      final away = row.awayCorners!.toDouble();
      if (home < 0 || away < 0 || home > 40 || away > 40) {
        continue;
      }
      final date = DateTime.tryParse(row.date);
      if (date == null) {
        continue;
      }
      if (trainedThrough == null || date.isAfter(trainedThrough)) {
        trainedThrough = date;
      }
      count += 1;
      homeSum += home;
      awaySum += away;
      homeSquares += home * home;
      awaySquares += away * away;
      products += home * away;
    }
    if (count < 2) {
      return BivariateCornerFit(
        leagueCode: league.code,
        homeMean: 0,
        awayMean: 0,
        homeVariance: 0,
        awayVariance: 0,
        covariance: 0,
        matches: count,
        trainedThrough: trainedThrough,
      );
    }
    final n = count.toDouble();
    final homeMean = homeSum / n;
    final awayMean = awaySum / n;
    final denominator = n - 1;
    return BivariateCornerFit(
      leagueCode: league.code,
      homeMean: homeMean,
      awayMean: awayMean,
      homeVariance: max(
        (homeSquares - n * homeMean * homeMean) / denominator,
        0,
      ),
      awayVariance: max(
        (awaySquares - n * awayMean * awayMean) / denominator,
        0,
      ),
      covariance: (products - n * homeMean * awayMean) / denominator,
      matches: count,
      trainedThrough: trainedThrough,
    );
  }
}
