import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _adjustedHomeIndex = 24;
const _rawHomeRollingIndex = 4;

void main() {
  test('names every appended opponent-adjusted column', () {
    expect(footballFeatureNames, hasLength(FootballMobileEngine.featureCount));
    expect(footballFeatureNames[_adjustedHomeIndex], contains('對手校正'));
    expect(footballFeatureNames.last, contains('對手校正'));
  });

  test('the same corner count counts for more against a tight defence', () {
    final engine = FootballMobileEngine();
    final leaky = engine.buildTrainingRows(
      _dataset(opponentConceded: 9),
      _config,
    );
    final tight = engine.buildTrainingRows(
      _dataset(opponentConceded: 2),
      _config,
    );

    final leakyRow = leaky.last.features;
    final tightRow = tight.last.features;
    // Focus took the same six corners in both histories, so the credit it gets
    // has to come from the opponent column and lean towards the tight defence.
    expect(
      tightRow[_adjustedHomeIndex] / tightRow[_rawHomeRollingIndex],
      greaterThan(
        leakyRow[_adjustedHomeIndex] / leakyRow[_rawHomeRollingIndex],
      ),
    );
    expect(
      tightRow[_adjustedHomeIndex],
      greaterThan(leakyRow[_adjustedHomeIndex]),
    );
  });

  test('the adjustment stays bounded when an opponent has no history', () {
    final rows = FootballMobileEngine().buildTrainingRows(
      _dataset(opponentConceded: 0),
      _config,
    );
    final adjusted = rows.last.features[_adjustedHomeIndex];
    expect(adjusted, greaterThan(0));
    expect(adjusted, lessThan(40));
  });
}

const _config = FootballLeagueConfig(
  code: 'E0',
  name: '英超',
  supportCode: 'E1',
  supportName: '英冠',
);

/// History where `Focus` always takes six corners, and its opponents differ only
/// in how many corners they concede to everyone else.
MobileFootballDataset _dataset({required int opponentConceded}) {
  final rows = <FootballMatchRecord>[];
  for (var index = 0; index < 30; index++) {
    final date = DateTime.utc(2024, 1, 1).add(Duration(days: index));
    final day = date.toIso8601String().substring(0, 10);
    rows.add(
      _record(
        date: day,
        homeTeam: 'Rival${index % 3}',
        awayTeam: 'Filler${index % 4}',
        homeCorners: 5,
        awayCorners: opponentConceded,
      ),
    );
    rows.add(
      _record(
        date: day,
        homeTeam: 'Focus',
        awayTeam: 'Rival${index % 3}',
        homeCorners: 6,
        awayCorners: 4,
      ),
    );
  }
  rows.add(
    _record(
      date: '2024-03-01',
      homeTeam: 'Focus',
      awayTeam: 'Rival0',
      homeCorners: 6,
      awayCorners: 4,
    ),
  );
  return MobileFootballDataset(
    schemaVersion: 1,
    datasetVersion: 'opponent-adjusted-test',
    generatedAt: DateTime.now().toIso8601String(),
    leagues: const [_config],
    rows: rows,
    fixtures: const [],
  );
}

FootballMatchRecord _record({
  required String date,
  required String homeTeam,
  required String awayTeam,
  required int homeCorners,
  required int awayCorners,
}) => FootballMatchRecord(
  division: 'E0',
  date: date,
  homeTeam: homeTeam,
  awayTeam: awayTeam,
  homeCorners: homeCorners,
  awayCorners: awayCorners,
  homeGoals: 1,
  awayGoals: 1,
  homeShots: 12,
  awayShots: 11,
  homeShotsOnTarget: 4,
  awayShotsOnTarget: 4,
  homeOdds: 2.1,
  drawOdds: 3.3,
  awayOdds: 3.2,
  over25Odds: 1.9,
  under25Odds: 1.9,
);
