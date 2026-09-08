import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture congestion, built only from free schedule dates: how long a side
/// rested and how many matches its legs already carry.
void main() {
  final engine = FootballMobileEngine();

  test('the congestion columns are appended, never inserted', () {
    final rows = engine.buildTrainingRows(_dataset(gapDays: 7), league);

    expect(footballFeatureNames, hasLength(FootballMobileEngine.featureCount));
    expect(rows.first.features, hasLength(FootballMobileEngine.featureCount));
    expect(footballFeatureNames[29], '客隊近5場被xG');
    expect(footballFeatureNames[30], '主隊休息日數');
    expect(footballFeatureNames[31], '客隊休息日數');
    expect(footballFeatureNames[32], '主隊近14日場數');
    expect(footballFeatureNames[33], '客隊近14日場數');
  });

  test('a congested schedule reads shorter rest and more matches', () {
    final tight = engine.buildTrainingRows(_dataset(gapDays: 3), league).last;
    final loose = engine.buildTrainingRows(_dataset(gapDays: 10), league).last;

    expect(tight.features[30], lessThan(loose.features[30]));
    expect(tight.features[32], greaterThan(loose.features[32]));
    expect(loose.features[32], lessThanOrEqualTo(2 / 3));
  });

  test('a side never seen before falls back instead of reading zero', () {
    final rows = engine.buildTrainingRows(_dataset(gapDays: 7), league);

    // The first row of the league has no history at all: rest days take the
    // neutral default and the fortnight count is genuinely zero matches.
    expect(rows.first.features[30], closeTo(7 / 14, 1e-9));
    expect(rows.first.features[31], closeTo(7 / 14, 1e-9));
    expect(rows.first.features[32], 0);
  });

  test('support-competition matches still tire the legs', () {
    final withCup = engine
        .buildTrainingRows(_dataset(gapDays: 10, supportMatches: true), league)
        .last;
    final without = engine
        .buildTrainingRows(_dataset(gapDays: 10), league)
        .last;

    expect(withCup.features[32], greaterThan(without.features[32]));
  });

  test('only matches before kick-off count towards congestion', () {
    final rows = engine.buildTrainingRows(_dataset(gapDays: 3), league);

    // Same-day fixtures are folded into the state after the whole date is
    // scored, so a row can never read its own match as fatigue.
    for (final row in rows) {
      expect(row.features[32] * 3, lessThanOrEqualTo(5));
      expect(row.features[30] * 14, greaterThanOrEqualTo(2));
    }
  });
}

MobileFootballDataset _dataset({
  required int gapDays,
  bool supportMatches = false,
}) {
  final rows = <FootballMatchRecord>[];
  for (var index = 0; index < 30; index++) {
    final date = DateTime.utc(2025, 1, 1).add(Duration(days: index * gapDays));
    rows.add(_match(division: 'E0', date: date, index: index));
    if (supportMatches) {
      rows.add(
        _match(
          division: 'E1',
          date: date.add(const Duration(days: 3)),
          index: index,
        ),
      );
    }
  }
  return MobileFootballDataset(
    schemaVersion: 1,
    datasetVersion: 'congestion',
    generatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    leagues: const [league],
    rows: rows,
    fixtures: const [],
  );
}

const league = FootballLeagueConfig(
  code: 'E0',
  name: '英超',
  supportCode: 'E1',
  supportName: '英冠',
);

FootballMatchRecord _match({
  required String division,
  required DateTime date,
  required int index,
}) => FootballMatchRecord(
  division: division,
  date: date.toIso8601String().substring(0, 10),
  homeTeam: 'T${index % 2}',
  awayTeam: 'T${(index + 1) % 2}',
  homeCorners: 5 + index % 4,
  awayCorners: 4 + index % 3,
  homeGoals: index % 3,
  awayGoals: (index + 1) % 3,
  homeShots: 12,
  awayShots: 11,
  homeShotsOnTarget: 5,
  awayShotsOnTarget: 4,
  homeOdds: 2,
  drawOdds: 3.3,
  awayOdds: 3.4,
  over25Odds: 1.9,
  under25Odds: 1.9,
);
