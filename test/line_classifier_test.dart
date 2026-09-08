import 'dart:math';

import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/services/football_mobile_engine.dart';
import 'package:edgewise/services/line_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('learns a line it can separate and releases it', () {
    final rows = _signalRows(360);
    final set = trainLineClassifiers(
      development: rows.take(240).toList(),
      calibration: rows.skip(240).take(60).toList(),
      holdout: rows.skip(300).toList(),
    );

    final model = set.adoptedFor(9.5);
    expect(model, isNotNull);
    expect(model!.brier, lessThan(model.baselineBrier));
    expect(model.brier, lessThan(model.constantBrier));
    // Adoption needs the gain to be large next to its own standard error, not
    // merely a smaller number.
    expect(model.confidence, greaterThan(1.64));
    expect(model.samples, 60);
    // The separating column is feature 0, so the two ends of it have to give
    // clearly different probabilities.
    final low = model.overProbability(_features(0.2));
    final high = model.overProbability(_features(0.9));
    expect(high, greaterThan(low + 0.3));
    expect(low, greaterThanOrEqualTo(0));
    expect(high, lessThanOrEqualTo(1));
  });

  test('refuses every line when the features carry no signal', () {
    final rows = _noiseRows(360);
    final set = trainLineClassifiers(
      development: rows.take(240).toList(),
      calibration: rows.skip(240).take(60).toList(),
      holdout: rows.skip(300).toList(),
    );

    expect(set.lines, isNotEmpty);
    expect(set.adoptedCount, 0);
    expect(set.adoptedFor(9.5), isNull);
    expect(set.note, contains('未在統計上勝過基準'));
    // The refused lines stay in the model so the app can disclose that they
    // were tried, and every one of them is inside the noise band.
    expect(set.lines.every((model) => model.confidence < 1.64), isTrue);
  });

  test('does not fit anything on too few rows', () {
    final rows = _signalRows(90);
    final set = trainLineClassifiers(
      development: rows.take(60).toList(),
      calibration: rows.skip(60).take(15).toList(),
      holdout: rows.skip(75).toList(),
    );

    expect(set.lines, isEmpty);
    expect(set.note, contains('樣本不足'));
  });

  test('skips a line one side of which almost never happens', () {
    final rows = _signalRows(360);
    final set = trainLineClassifiers(
      development: rows.take(240).toList(),
      calibration: rows.skip(240).take(60).toList(),
      holdout: rows.skip(300).toList(),
      lines: const [0.5],
    );

    expect(set.lines, isEmpty);
    expect(set.note, contains('沒有一條盤口'));
  });

  test('survives a JSON round trip inside the league model', () {
    final rows = _signalRows(360);
    final set = trainLineClassifiers(
      development: rows.take(240).toList(),
      calibration: rows.skip(240).take(60).toList(),
      holdout: rows.skip(300).toList(),
    );
    final league = _leagueModel(set);

    final restored = MobileFootballLeagueModel.fromJson(league.toJson());
    final model = restored.lineClassifiers.adoptedFor(9.5);

    expect(model, isNotNull);
    expect(
      model!.overProbability(_features(0.9)),
      closeTo(set.adoptedFor(9.5)!.overProbability(_features(0.9)), 0.000001),
    );
  });

  test('a model stored before line classifiers existed reads as empty', () {
    final json = _leagueModel(LineClassifierSet.empty).toJson();

    expect(json.containsKey('lineClassifiers'), isFalse);
    expect(
      MobileFootballLeagueModel.fromJson(json).lineClassifiers.lines,
      isEmpty,
    );
  });

  test('an unadopted line is never read at prediction time', () {
    final refused = LineClassifierSet(
      lines: [
        LineProbabilityModel(
          line: 9.5,
          means: List<double>.filled(FootballMobileEngine.featureCount, 0),
          scales: List<double>.filled(FootballMobileEngine.featureCount, 1),
          weights: List<double>.filled(FootballMobileEngine.featureCount, 0),
          intercept: 5,
          calibrationSlope: 1,
          calibrationShift: 0,
          samples: 50,
          brier: 0.3,
          baselineBrier: 0.2,
          constantBrier: 0.24,
          confidence: -1.2,
          adopted: false,
        ),
      ],
    );

    expect(refused.adoptedFor(9.5), isNull);
    expect(refused.adoptedCount, 0);
  });

  test('calibration is fitted on rows the weights never saw', () {
    final rows = _signalRows(360);
    final development = rows.take(240).toList();
    final calibration = rows.skip(240).take(60).toList();
    final holdout = rows.skip(300).toList();

    final set = trainLineClassifiers(
      development: development,
      calibration: calibration,
      holdout: holdout,
    );
    final model = set.adoptedFor(9.5)!;

    // Platt scaling that reproduces the raw model exactly would mean the
    // calibration window was ignored; a moved slope or shift is the evidence
    // that it was used.
    expect(
      model.calibrationSlope != 1.0 || model.calibrationShift != 0.0,
      isTrue,
    );
    expect(model.calibrationSlope, greaterThan(0));
  });
}

MobileFootballLeagueModel _leagueModel(LineClassifierSet set) =>
    MobileFootballLeagueModel(
      code: 'E0',
      featureMeans: List<double>.filled(FootballMobileEngine.featureCount, 0),
      featureScales: List<double>.filled(FootballMobileEngine.featureCount, 1),
      homeWeights: List<double>.filled(FootballMobileEngine.featureCount, 0),
      homeIntercept: 1.7,
      awayWeights: List<double>.filled(FootballMobileEngine.featureCount, 0),
      awayIntercept: 1.6,
      totalWeights: List<double>.filled(FootballMobileEngine.featureCount, 0),
      totalIntercept: 2.3,
      useModel: false,
      trainingMatches: 300,
      holdoutMatches: 60,
      mae: 2.7,
      baselineMae: 2.7,
      brierOver95: 0.25,
      baselineBrierOver95: 0.25,
      dispersion: 0.1,
      lineClassifiers: set,
    );

List<double> _features(double signal) => [
  signal,
  for (var index = 1; index < FootballMobileEngine.featureCount; index++) 0.5,
];

/// Rows whose first feature decides the total, with a baseline that does not
/// know it: the classifier should be able to beat the baseline here.
List<FootballTrainingRow> _signalRows(int count) {
  final random = Random(7);
  return [
    for (var index = 0; index < count; index++)
      () {
        final signal = random.nextDouble();
        final total = (4 + (signal * 14).round()).clamp(2, 20);
        final home = total ~/ 2;
        return FootballTrainingRow(
          matchId: 'E0:$index',
          date: DateTime.utc(
            2024,
            1,
            1,
          ).add(Duration(days: index)).toIso8601String().substring(0, 10),
          features: _features(signal),
          homeCorners: home,
          awayCorners: total - home,
          baselineHome: 5,
          baselineAway: 5,
        );
      }(),
  ];
}

/// Rows whose total is independent of every feature, so nothing can be learned
/// and the gate has to refuse.
List<FootballTrainingRow> _noiseRows(int count) {
  final random = Random(11);
  return [
    for (var index = 0; index < count; index++)
      () {
        final total = 6 + random.nextInt(9);
        final home = total ~/ 2;
        return FootballTrainingRow(
          matchId: 'E0:$index',
          date: DateTime.utc(
            2024,
            1,
            1,
          ).add(Duration(days: index)).toIso8601String().substring(0, 10),
          features: _features(random.nextDouble()),
          homeCorners: home,
          awayCorners: total - home,
          baselineHome: 5,
          baselineAway: 5,
        );
      }(),
  ];
}
