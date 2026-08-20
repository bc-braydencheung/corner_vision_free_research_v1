import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/forecast_data.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// The free shot-quality proxy: free sources publish shot counts but not shot
/// locations, so an on-target attempt has to weigh far more than a wide one.
void main() {
  const league = FootballLeagueConfig(
    code: 'E0',
    name: '英超',
    supportCode: 'E1',
    supportName: '英冠',
  );
  final engine = FootballMobileEngine();

  test('the proxy columns are appended, never inserted', () {
    final rows = engine.buildTrainingRows(_dataset(), league);

    expect(footballFeatureNames, hasLength(FootballMobileEngine.featureCount));
    expect(rows.first.features, hasLength(FootballMobileEngine.featureCount));
    // The older columns keep their meaning so a model released before the
    // proxy existed still lines up with the front of the vector.
    expect(footballFeatureNames[21], '休息日數差');
    expect(footballFeatureNames[22], contains('射門質量代理'));
    expect(footballFeatureNames[23], contains('射門質量代理'));
  });

  test('accurate shooting scores above the same volume off target', () {
    final accurate = engine
        .buildTrainingRows(_dataset(homeOnTarget: 8), league)
        .last
        .features[22];
    final wild = engine
        .buildTrainingRows(_dataset(homeOnTarget: 2), league)
        .last
        .features[22];

    expect(accurate, greaterThan(wild));
    // Same number of attempts either way: only the quality moved.
    expect(wild, greaterThan(0));
  });

  test('missing shot columns leave the proxy at its default', () {
    final rows = engine.buildTrainingRows(_dataset(shots: null), league);

    expect(rows.last.features[22], closeTo(1.35, 1e-9));
    expect(rows.last.features[23], closeTo(1.15, 1e-9));
  });

  test('a model released before the proxy still predicts', () {
    final dataset = _dataset();
    // A model that only carries the 22 older columns must not read past its
    // own statistics: it is used as released instead of being discarded.
    final released = MobileFootballModel(
      version: 'released-before-proxy',
      datasetVersion: dataset.datasetVersion,
      trainedThrough: const {'E0': '2025-12-31'},
      leagues: [
        MobileFootballLeagueModel(
          code: 'E0',
          featureMeans: List<double>.filled(
            FootballMobileEngine.minimumFeatureCount,
            0,
          ),
          featureScales: List<double>.filled(
            FootballMobileEngine.minimumFeatureCount,
            1,
          ),
          homeWeights: List<double>.filled(
            FootballMobileEngine.minimumFeatureCount,
            0,
          ),
          homeIntercept: 1.7,
          awayWeights: List<double>.filled(
            FootballMobileEngine.minimumFeatureCount,
            0,
          ),
          awayIntercept: 1.6,
          totalWeights: List<double>.filled(
            FootballMobileEngine.minimumFeatureCount,
            0,
          ),
          totalIntercept: 2.3,
          trainingMatches: 300,
          holdoutMatches: 60,
          mae: 2.6,
          baselineMae: 2.7,
          brierOver95: 0.24,
          baselineBrierOver95: 0.25,
          dispersion: 8,
          useModel: true,
        ),
      ],
    );

    final leagues = engine.predictLeagues(
      bundled: _bundled(),
      dataset: dataset,
      model: released,
    );

    expect(leagues.single.forecasts, hasLength(1));
    expect(
      leagues.single.forecasts.single.expectedTotalCorners,
      greaterThan(0),
    );
  });
}

MobileFootballDataset _dataset({int? shots = 14, int homeOnTarget = 5}) =>
    MobileFootballDataset(
      schemaVersion: 1,
      datasetVersion: 'shot-quality',
      generatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      leagues: const [
        FootballLeagueConfig(
          code: 'E0',
          name: '英超',
          supportCode: 'E1',
          supportName: '英冠',
        ),
      ],
      rows: [
        for (var index = 0; index < 40; index++)
          FootballMatchRecord(
            division: 'E0',
            date: DateTime.utc(
              2025,
              1,
              1,
            ).add(Duration(days: index)).toIso8601String().substring(0, 10),
            homeTeam: 'T${index % 4}',
            awayTeam: 'T${(index + 1) % 4}',
            homeCorners: 5 + index % 4,
            awayCorners: 4 + index % 3,
            homeGoals: index % 3,
            awayGoals: (index + 1) % 3,
            homeShots: shots,
            awayShots: shots,
            homeShotsOnTarget: shots == null ? null : homeOnTarget,
            awayShotsOnTarget: shots == null ? null : 4,
            homeOdds: 2,
            drawOdds: 3.3,
            awayOdds: 3.4,
            over25Odds: 1.9,
            under25Odds: 1.9,
          ),
      ],
      fixtures: [
        FootballMatchRecord(
          division: 'E0',
          date: '2025-03-01',
          homeTeam: 'T0',
          awayTeam: 'T1',
          homeOdds: 2,
          drawOdds: 3.3,
          awayOdds: 3.4,
          over25Odds: 1.9,
          under25Odds: 1.9,
        ),
      ],
    );

List<LeagueForecastData> _bundled() => const [
  LeagueForecastData(
    code: 'E0',
    name: '英超',
    supportName: '英冠',
    status: '測試',
    model: ModelSummary(
      selectedCandidate: 'dynamic',
      selectedCandidateLabel: 'Dynamic',
      trainedThrough: '2025-12-31',
      firstSeason: '2024/25',
      lastSeason: '2025/26',
      trainingMatches: 100,
      supportMatches: 0,
      supportName: '英冠',
      validationMatches: 10,
      holdoutMatches: 10,
      maeTotalCorners: 3,
      baselineMaeHoldout: 3,
      maeSkillVsDynamicPercent: 0,
      withinTwoHoldout: 0.5,
      brierOver9_5: 0.25,
      brierSkillOver9_5Percent: 0,
      calibrationErrorOver9_5: 0.05,
    ),
    forecasts: [],
    recentBacktests: [],
  ),
];
