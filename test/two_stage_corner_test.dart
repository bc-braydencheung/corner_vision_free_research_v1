import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/corner_strength_model.dart';
import 'package:edgewise/services/two_stage_corner_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _league = FootballLeagueConfig(
  code: 'E0',
  name: 'Premier League',
  supportCode: 'E1',
  supportName: 'Championship',
);

FootballMatchRecord _row({
  required String date,
  required String home,
  required String away,
  required int homeShots,
  required int awayShots,
  required int homeCorners,
  required int awayCorners,
  String division = 'E0',
  String? referee,
}) => FootballMatchRecord(
  division: division,
  date: date,
  homeTeam: home,
  awayTeam: away,
  homeShots: homeShots,
  awayShots: awayShots,
  homeCorners: homeCorners,
  awayCorners: awayCorners,
  referee: referee,
);

List<FootballMatchRecord> _history({
  required int matches,
  required int homeShots,
  required int homeCorners,
  String? referee,
}) {
  final rows = <FootballMatchRecord>[];
  for (var index = 0; index < matches; index++) {
    final day = index + 1;
    rows.add(
      _row(
        date: '2024-01-${day.toString().padLeft(2, '0')}',
        home: 'Shooters',
        away: 'Blockers',
        homeShots: homeShots,
        awayShots: 11,
        homeCorners: homeCorners,
        awayCorners: 4,
        referee: referee,
      ),
    );
  }
  return rows;
}

void main() {
  group('TwoStageCornerModel', () {
    test('returns the empty table when no row carries shot counts', () {
      final rows = [
        FootballMatchRecord(
          division: 'E0',
          date: '2024-01-01',
          homeTeam: 'A',
          awayTeam: 'B',
          homeCorners: 5,
          awayCorners: 4,
        ),
      ];
      final table = const TwoStageCornerModel().fit(rows, _league);
      expect(table.matches, 0);
      expect(table.teams, isEmpty);
    });

    test('learns a high shot volume team', () {
      final table = const TwoStageCornerModel().fit(
        _history(matches: 40, homeShots: 22, homeCorners: 9),
        _league,
      );
      final shooters = table.resolve('Shooters');
      expect(shooters, isNotNull);
      expect(shooters!.shotAttack, greaterThan(0));
      expect(table.matches, 40);
      expect(table.trainedThrough, isNotNull);
    });

    test('separates shot volume from conversion', () {
      final volume = const TwoStageCornerModel().fit(
        _history(matches: 40, homeShots: 24, homeCorners: 8),
        _league,
      );
      final conversion = const TwoStageCornerModel().fit(
        _history(matches: 40, homeShots: 12, homeCorners: 8),
        _league,
      );
      final volumeTeam = volume.resolve('Shooters')!;
      final conversionTeam = conversion.resolve('Shooters')!;
      expect(volumeTeam.shotAttack, greaterThan(conversionTeam.shotAttack));
      expect(conversionTeam.conversion, greaterThan(volumeTeam.conversion));
    });

    test('prior needs both teams to be known', () {
      final table = const TwoStageCornerModel().fit(
        _history(matches: 30, homeShots: 15, homeCorners: 6),
        _league,
      );
      expect(
        table.priorFor(homeTeam: 'Shooters', awayTeam: 'Unknown Town'),
        isNull,
      );
      expect(
        table.priorFor(homeTeam: 'Shooters', awayTeam: 'Blockers'),
        isNotNull,
      );
    });

    test('prior total tracks the observed corner level', () {
      final low = const TwoStageCornerModel()
          .fit(_history(matches: 60, homeShots: 12, homeCorners: 3), _league)
          .priorFor(homeTeam: 'Shooters', awayTeam: 'Blockers')!;
      final high = const TwoStageCornerModel()
          .fit(_history(matches: 60, homeShots: 20, homeCorners: 9), _league)
          .priorFor(homeTeam: 'Shooters', awayTeam: 'Blockers')!;
      expect(high.totalMean, greaterThan(low.totalMean));
      expect(low.totalMean, greaterThan(0));
    });

    test('a thin history yields an unreliable prior', () {
      final table = const TwoStageCornerModel().fit(
        _history(matches: 3, homeShots: 14, homeCorners: 6),
        _league,
      );
      final prior = table.priorFor(homeTeam: 'Shooters', awayTeam: 'Blockers')!;
      expect(prior.teamMatches, lessThan(6));
      expect(prior.reliable, isFalse);
    });

    test('support division matches enter with a lower weight', () {
      final rows = <FootballMatchRecord>[
        for (var index = 0; index < 20; index++)
          _row(
            date: '2024-02-${(index + 1).toString().padLeft(2, '0')}',
            home: 'Shooters',
            away: 'Blockers',
            homeShots: 20,
            awayShots: 10,
            homeCorners: 8,
            awayCorners: 4,
            division: 'E1',
          ),
      ];
      final table = const TwoStageCornerModel().fit(rows, _league);
      expect(table.matches, 0);
      expect(table.resolve('Shooters')!.matches, closeTo(20 * 0.55, 1e-9));
    });

    test('a rarely seen referee never moves the mean', () {
      final rows = _history(
        matches: 8,
        homeShots: 16,
        homeCorners: 7,
        referee: 'A Novice',
      );
      final table = const TwoStageCornerModel().fit(rows, _league);
      final profile = table.resolveReferee('A Novice');
      expect(profile, isNotNull);
      expect(profile!.reliable, isFalse);
      final withReferee = table.priorFor(
        homeTeam: 'Shooters',
        awayTeam: 'Blockers',
        referee: 'A Novice',
      )!;
      final without = table.priorFor(
        homeTeam: 'Shooters',
        awayTeam: 'Blockers',
      )!;
      expect(withReferee.totalMean, closeTo(without.totalMean, 1e-9));
    });

    test('a high corner referee lifts the mean once trusted', () {
      final rows = <FootballMatchRecord>[
        for (var index = 0; index < 40; index++)
          _row(
            date: '2024-03-${(index % 28 + 1).toString().padLeft(2, '0')}',
            home: index.isEven ? 'Shooters' : 'Blockers',
            away: index.isEven ? 'Blockers' : 'Shooters',
            homeShots: 16,
            awayShots: 15,
            homeCorners: index.isEven ? 12 : 3,
            awayCorners: index.isEven ? 11 : 3,
            referee: index.isEven ? 'M Whistle' : 'Q Quiet',
          ),
      ];
      final table = const TwoStageCornerModel().fit(rows, _league);
      final busy = table.resolveReferee('M Whistle')!;
      final quiet = table.resolveReferee('Q Quiet')!;
      expect(busy.matches, 20);
      expect(busy.logFactor, greaterThan(quiet.logFactor));
      expect(busy.reliable, isTrue);
      final withBusy = table.priorFor(
        homeTeam: 'Shooters',
        awayTeam: 'Blockers',
        referee: 'M Whistle',
      )!;
      final withQuiet = table.priorFor(
        homeTeam: 'Shooters',
        awayTeam: 'Blockers',
        referee: 'Q Quiet',
      )!;
      expect(withBusy.totalMean, greaterThan(withQuiet.totalMean));
    });

    test('referee names are matched across spellings', () {
      expect(normaliseRefereeName('M. Oliver'), 'm oliver');
      expect(normaliseRefereeName('  m   oliver '), 'm oliver');
      expect(normaliseRefereeName('***'), '');
    });

    test('a stale state decays towards the league mean', () {
      final table = const TwoStageCornerModel().fit(
        _history(matches: 40, homeShots: 24, homeCorners: 10),
        _league,
      );
      final fresh = table.priorFor(
        homeTeam: 'Shooters',
        awayTeam: 'Blockers',
        kickOff: DateTime.parse('2024-02-11'),
      )!;
      final stale = table.priorFor(
        homeTeam: 'Shooters',
        awayTeam: 'Blockers',
        kickOff: DateTime.parse('2025-02-11'),
      )!;
      expect(stale.totalMean, lessThan(fresh.totalMean));
    });
  });

  group('combineCornerPriors', () {
    const reliable = CornerMeanPrior(
      homeMean: 6,
      awayMean: 4,
      logVariance: 0.01,
      dispersion: 0.05,
      teamMatches: 40,
    );
    const thin = CornerMeanPrior(
      homeMean: 3,
      awayMean: 2,
      logVariance: 0.4,
      dispersion: 0.02,
      teamMatches: 2,
    );

    test('returns null when neither prior exists', () {
      expect(combineCornerPriors(null, null), isNull);
    });

    test('returns the only prior available', () {
      expect(combineCornerPriors(reliable, null), same(reliable));
      expect(combineCornerPriors(null, reliable), same(reliable));
    });

    test('ignores an unreliable prior', () {
      expect(combineCornerPriors(reliable, thin), same(reliable));
      expect(combineCornerPriors(thin, reliable), same(reliable));
    });

    test('keeps an unreliable prior when it is all there is', () {
      expect(combineCornerPriors(thin, null), same(thin));
    });

    test('blends two reliable priors inside their totals', () {
      const other = CornerMeanPrior(
        homeMean: 8,
        awayMean: 6,
        logVariance: 0.01,
        dispersion: 0.09,
        teamMatches: 30,
      );
      final blended = combineCornerPriors(reliable, other)!;
      expect(blended.totalMean, greaterThan(reliable.totalMean));
      expect(blended.totalMean, lessThan(other.totalMean));
      expect(blended.logVariance, lessThan(reliable.logVariance));
      expect(blended.dispersion, 0.09);
      expect(blended.teamMatches, 40);
    });

    test('the more certain prior anchors the home/away split', () {
      const certain = CornerMeanPrior(
        homeMean: 7,
        awayMean: 3,
        logVariance: 0.005,
        dispersion: 0,
        teamMatches: 50,
      );
      const vague = CornerMeanPrior(
        homeMean: 4,
        awayMean: 8,
        logVariance: 0.04,
        dispersion: 0,
        teamMatches: 20,
      );
      final blended = combineCornerPriors(vague, certain)!;
      expect(blended.homeMean / blended.totalMean, closeTo(0.7, 1e-9));
    });
  });
}
