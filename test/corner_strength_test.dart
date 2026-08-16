import 'dart:math';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/hkjc_football.dart';
import 'package:edgewise/services/corner_strength_model.dart';
import 'package:edgewise/services/count_distribution.dart';
import 'package:edgewise/services/hkjc_corner_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _league = FootballLeagueConfig(
  code: 'E0',
  name: '英格蘭超級聯賽',
  supportCode: 'E1',
  supportName: '英冠',
);

FootballMatchRecord _match({
  required String date,
  required String home,
  required String away,
  required int homeCorners,
  required int awayCorners,
  String division = 'E0',
}) => FootballMatchRecord(
  division: division,
  date: date,
  homeTeam: home,
  awayTeam: away,
  homeCorners: homeCorners,
  awayCorners: awayCorners,
  homeGoals: 1,
  awayGoals: 1,
);

/// Two seasons where one club always wins many corners and one always few.
List<FootballMatchRecord> _history() {
  final rows = <FootballMatchRecord>[];
  var day = DateTime.utc(2025, 8, 10);
  for (var round = 0; round < 40; round++) {
    day = day.add(const Duration(days: 7));
    final date = day.toIso8601String().substring(0, 10);
    rows.add(
      _match(
        date: date,
        home: 'Corner City',
        away: 'Mid Town',
        homeCorners: 10,
        awayCorners: 4,
      ),
    );
    rows.add(
      _match(
        date: date,
        home: 'Quiet Rovers',
        away: 'Other Mid',
        homeCorners: 2,
        awayCorners: 3,
      ),
    );
  }
  return rows;
}

HkjcFootballFixture _fixture({
  required String home,
  required String away,
  required List<HkjcMarketLine> lines,
}) => HkjcFootballFixture(
  matchId: 'p1',
  frontEndId: 'FB9',
  leagueCode: 'E0',
  tournamentCode: 'EPL',
  tournamentName: '英格蘭超級聯賽',
  kickOffTime: DateTime.utc(2026, 8, 22),
  status: 'PREEVENT',
  homeTeam: '主',
  awayTeam: '客',
  homeTeamEnglish: home,
  awayTeamEnglish: away,
  cornerLines: lines,
);

const _line = HkjcMarketLine(
  lineId: '1',
  condition: '9.5',
  line: 9.5,
  main: true,
  status: 'AVAILABLE',
  highOdds: 1.9,
  lowOdds: 1.9,
);

void main() {
  group('negative binomial counts', () {
    test('collapses to the Poisson when there is no dispersion', () {
      const poisson = NegativeBinomialCount.poisson(9.4);
      const nb2 = NegativeBinomialCount(mean: 9.4, dispersion: 0);

      for (final count in [0, 1, 5, 9, 14]) {
        expect(nb2.pmf(count), closeTo(poisson.pmf(count), 1e-12));
      }
      expect(poisson.variance, closeTo(9.4, 1e-12));
    });

    test('keeps the mean but widens the tails', () {
      const mean = 9.5;
      const poisson = NegativeBinomialCount.poisson(mean);
      const nb2 = NegativeBinomialCount(mean: mean, dispersion: 0.05);

      final masses = nb2.masses(maxCount: 60);
      final total = masses.reduce((a, b) => a + b);
      var expected = 0.0;
      for (var count = 0; count < masses.length; count++) {
        expected += count * masses[count];
      }

      expect(total, closeTo(1, 1e-9));
      expect(expected, closeTo(mean, 0.05));
      expect(nb2.variance, greaterThan(poisson.variance));
      // A fatter tail on both ends of the same mean.
      expect(nb2.survival(15), greaterThan(poisson.survival(15)));
      expect(nb2.cdf(4), greaterThan(poisson.cdf(4)));
    });

    test('estimates dispersion from overdispersed residuals only', () {
      final means = List<double>.filled(200, 9.5);
      final equidispersed = <double>[];
      final overdispersed = <double>[];
      final random = Random(7);
      for (var index = 0; index < 200; index++) {
        equidispersed.add(9.5 + (random.nextDouble() - 0.5) * 2 * sqrt(9.5));
        overdispersed.add(index.isEven ? 3 : 16);
      }

      expect(estimateDispersion(equidispersed, means), lessThan(0.02));
      expect(estimateDispersion(overdispersed, means), greaterThan(0.1));
      expect(
        estimateDispersion(const [10, 9], const [9.5, 9.5]),
        0,
        reason: 'a two match sample can never justify a dispersion parameter',
      );
    });
  });

  group('team corner strengths', () {
    test('separates a high corner side from a low corner side', () {
      final table = const CornerStrengthModel().fit(_history(), _league);

      final city = table.resolve('Corner City')!;
      final rovers = table.resolve('Quiet Rovers')!;

      expect(city.attack, greaterThan(rovers.attack));
      expect(table.matches, 80);
      expect(table.trainedThrough, isNotNull);
      // Repeated evidence must shrink the posterior variance.
      expect(city.attackVariance, lessThan(CornerStrengthModel.priorVariance));
    });

    test('an unknown club yields no prior instead of a guess', () {
      final table = const CornerStrengthModel().fit(_history(), _league);

      expect(table.resolve('Nowhere Athletic'), isNull);
      expect(
        table.priorFor(homeTeam: 'Corner City', awayTeam: 'Nowhere Athletic'),
        isNull,
      );
    });

    test('matches club spellings across the free sources', () {
      expect(normaliseTeamName('Ath Bilbao'), 'ath bilbao');
      expect(normaliseTeamName('Atlético Madrid'), 'atletico madrid');
      expect(normaliseTeamName('Brighton FC'), 'brighton');
      expect(normaliseTeamName('  '), '');
    });

    test('a stale rating reverts towards the league average', () {
      final table = const CornerStrengthModel().fit(_history(), _league);
      final fresh = table.priorFor(
        homeTeam: 'Corner City',
        awayTeam: 'Mid Town',
        kickOff: table.trainedThrough!.add(const Duration(days: 3)),
      )!;
      final stale = table.priorFor(
        homeTeam: 'Corner City',
        awayTeam: 'Mid Town',
        kickOff: table.trainedThrough!.add(const Duration(days: 300)),
      )!;

      expect(stale.totalMean, lessThan(fresh.totalMean));
      expect(stale.logVariance, greaterThan(fresh.logVariance));
    });
  });

  group('market blend', () {
    test('a reliable prior moves the market mean, but only partly', () {
      final table = const CornerStrengthModel().fit(_history(), _league);
      final prior = table.priorFor(
        homeTeam: 'Corner City',
        awayTeam: 'Mid Town',
        kickOff: table.trainedThrough!.add(const Duration(days: 3)),
      )!;
      expect(prior.reliable, isTrue);

      final fixture = _fixture(
        home: 'Corner City',
        away: 'Mid Town',
        lines: const [_line],
      );
      const market = HkjcCornerModel();
      final blended = HkjcCornerModel(prior: prior);

      final marketOnly = market.assess(fixture)!;
      final withPrior = blended.assess(fixture)!;

      expect(
        withPrior.marketExpectedCorners,
        closeTo(marketOnly.expectedCorners, 1e-9),
      );
      expect(withPrior.priorWeight, greaterThan(0));
      expect(withPrior.priorWeight, lessThan(1));
      expect(withPrior.priorExpectedCorners, closeTo(prior.totalMean, 1e-9));
      // The blend has to sit strictly between the two inputs.
      final low = min(prior.totalMean, withPrior.marketExpectedCorners);
      final high = max(prior.totalMean, withPrior.marketExpectedCorners);
      expect(withPrior.expectedCorners, greaterThan(low));
      expect(withPrior.expectedCorners, lessThan(high));
    });

    test('a thin prior is ignored', () {
      const thin = CornerMeanPrior(
        homeMean: 9,
        awayMean: 9,
        logVariance: 0.001,
        dispersion: 0.04,
        teamMatches: 2,
      );
      const model = HkjcCornerModel(prior: thin);

      expect(thin.reliable, isFalse);
      expect(model.priorWeight, 0);
      expect(model.dispersion, 0);
      expect(model.blendedMean(9.4), closeTo(9.4, 1e-12));
    });

    test('dispersion widens the model probabilities of a far line', () {
      const prior = CornerMeanPrior(
        homeMean: 5.2,
        awayMean: 4.6,
        logVariance: 0.004,
        dispersion: 0.06,
        teamMatches: 30,
      );
      const line = HkjcMarketLine(
        lineId: '2',
        condition: '13.5',
        line: 13.5,
        main: true,
        status: 'AVAILABLE',
        highOdds: 3.5,
        lowOdds: 1.3,
      );
      const equidispersed = HkjcCornerModel();
      const overdispersed = HkjcCornerModel(prior: prior);

      expect(overdispersed.dispersion, closeTo(0.06, 1e-12));
      expect(
        overdispersed.highOutcome(9.4, line).adjusted,
        greaterThan(equidispersed.highOutcome(9.4, line).adjusted),
      );
    });
  });
}
