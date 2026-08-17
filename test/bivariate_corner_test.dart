import 'dart:math';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/services/bivariate_corner_model.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _league = FootballLeagueConfig(
  code: 'E0',
  name: '英超',
  supportCode: 'E1',
  supportName: '英冠',
);

FootballMatchRecord _row({
  required int index,
  required int homeCorners,
  required int awayCorners,
  String division = 'E0',
}) {
  final date = DateTime.utc(2024, 1, 1).add(Duration(days: index));
  return FootballMatchRecord(
    division: division,
    date: date.toIso8601String().substring(0, 10),
    homeTeam: 'Home $index',
    awayTeam: 'Away $index',
    homeCorners: homeCorners,
    awayCorners: awayCorners,
    homeGoals: 1,
    awayGoals: 1,
    homeShots: 12,
    awayShots: 11,
    homeShotsOnTarget: 4,
    awayShotsOnTarget: 4,
  );
}

List<FootballMatchRecord> _correlated({
  required int matches,
  required double correlation,
}) {
  final random = Random(7);
  final rows = <FootballMatchRecord>[];
  for (var index = 0; index < matches; index++) {
    final shared = random.nextDouble() * 8;
    final home = 2 + shared;
    final away = correlation < 0 ? 10 - shared : 2 + shared;
    rows.add(
      _row(index: index, homeCorners: home.round(), awayCorners: away.round()),
    );
  }
  return rows;
}

void main() {
  test('measures a negative correlation when one side dominates', () {
    final fit = const BivariateCornerModel().fit(
      _correlated(matches: 400, correlation: -1),
      _league,
    );

    expect(fit.matches, 400);
    expect(fit.reliable, isTrue);
    expect(fit.correlation, lessThan(-0.5));
    expect(fit.note, contains('負相關'));
    // Perfectly offsetting counts make the total narrower than Poisson, and the
    // model must not sharpen itself on that.
    expect(fit.totalVariance, lessThan(fit.independentPoissonVariance));
    expect(fit.dispersionFor(fit.totalMean), 0);
  });

  test('measures a positive correlation in end-to-end matches', () {
    final fit = const BivariateCornerModel().fit(
      _correlated(matches: 400, correlation: 1),
      _league,
    );

    expect(fit.reliable, isTrue);
    expect(fit.correlation, greaterThan(0.5));
    expect(fit.note, contains('正相關'));
    expect(fit.totalVariance, greaterThan(fit.independentPoissonVariance));
    expect(fit.dispersionFor(fit.totalMean), greaterThan(0));
  });

  test('stays neutral until enough matches back the correlation', () {
    final fit = const BivariateCornerModel().fit(
      _correlated(matches: 40, correlation: 1),
      _league,
    );

    expect(fit.reliable, isFalse);
    expect(fit.dispersionFor(10), 0);
    expect(fit.note, contains('未採用'));
  });

  test('ignores other divisions and unfinished rows', () {
    final rows = [
      ..._correlated(matches: 10, correlation: 1),
      _row(index: 99, homeCorners: 5, awayCorners: 5, division: 'SP1'),
    ];
    final fit = const BivariateCornerModel().fit(rows, _league);

    expect(fit.matches, 10);
  });

  test('a wider measured joint total widens the model probabilities', () {
    final fit = const BivariateCornerModel().fit(
      _correlated(matches: 400, correlation: 1),
      _league,
    );
    final independent = const HkjcCornerModel();
    final joint = HkjcCornerModel(joint: fit);

    expect(independent.dispersionAt(10), 0);
    expect(joint.dispersionAt(10), greaterThan(0));
    // A wider total pulls an extreme tail probability towards 0.5.
    const line = HkjcMarketLine(
      lineId: 'l1',
      condition: '13.5',
      line: 13.5,
      main: true,
      status: 'AVAILABLE',
      highOdds: 2,
      lowOdds: 2,
    );
    final independentTail = independent.highOutcome(10, line);
    final jointTail = joint.highOutcome(10, line);
    expect(jointTail.adjusted, greaterThan(independentTail.adjusted));
  });
}
