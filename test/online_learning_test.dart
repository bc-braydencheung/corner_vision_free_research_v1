import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/online_learning.dart';
import 'package:edgewise/services/online_learning_service.dart';
import 'package:flutter_test/flutter_test.dart';

OnlineObservation observation({
  required int day,
  required bool outcome,
  double model = 0.5,
  double fallback = 0.5,
  bool missingData = false,
  bool voided = false,
  double marketShift = 0,
}) {
  return OnlineObservation(
    settledAt: DateTime.utc(2026, 1, 1).add(Duration(days: day)),
    outcome: outcome,
    predictions: {'model': model, 'fallback': fallback},
    missingData: missingData,
    voided: voided,
    marketShift: marketShift,
  );
}

ShadowForecast shadow({
  required int day,
  required double probability,
  int? actual,
  bool settled = true,
  double expected = 10,
}) {
  final date = DateTime.utc(2026, 1, 1).add(Duration(days: day));
  return ShadowForecast(
    id: 'shadow-$day',
    matchId: 'match-$day',
    leagueCode: 'E0',
    leagueName: '英超',
    homeTeam: 'Home',
    awayTeam: 'Away',
    matchDate: date,
    capturedAt: date.subtract(const Duration(hours: 3)),
    modelVersion: 'v1',
    expectedTotalCorners: expected,
    over9_5Probability: probability,
    referenceMae: 3,
    referenceBrier: 0.25,
    actualTotalCorners: actual,
    settledAt: settled && actual != null ? date : null,
  );
}

void main() {
  group('brierLoss', () {
    test('rewards a confident correct forecast', () {
      expect(brierLoss(0.9, true), closeTo(0.01, 1e-9));
      expect(brierLoss(0.9, false), closeTo(0.81, 1e-9));
    });

    test('a coin flip always costs a quarter', () {
      expect(brierLoss(0.5, true), closeTo(0.25, 1e-9));
      expect(brierLoss(0.5, false), closeTo(0.25, 1e-9));
    });

    test('clamps out-of-range probabilities', () {
      expect(brierLoss(1.4, true), closeTo(0, 1e-9));
      expect(brierLoss(-0.3, false), closeTo(0, 1e-9));
    });
  });

  group('HedgeEnsemble', () {
    test('starts uniform', () {
      final ensemble = HedgeEnsemble.uniform(['model', 'fallback']);
      expect(ensemble.weightOf('model'), closeTo(0.5, 1e-9));
      expect(ensemble.weightOf('fallback'), closeTo(0.5, 1e-9));
    });

    test('moves weight towards the member with the lower loss', () {
      final updated = HedgeEnsemble.uniform([
        'model',
        'fallback',
      ]).update({'model': 0.04, 'fallback': 0.64});
      expect(updated.weightOf('model'), greaterThan(0.5));
      expect(updated.weightOf('fallback'), lessThan(0.5));
    });

    test('keeps weights normalised and above the floor', () {
      var ensemble = HedgeEnsemble.uniform(['model', 'fallback']);
      for (var index = 0; index < 400; index++) {
        ensemble = ensemble.update({'model': 0.0, 'fallback': 1.0});
      }
      final total = ensemble.weights.values.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      expect(total, closeTo(1, 1e-9));
      expect(ensemble.weightOf('fallback'), greaterThanOrEqualTo(0.03));
      expect(ensemble.weightOf('model'), lessThanOrEqualTo(0.97));
    });

    test('blends only the members it has a forecast for', () {
      final ensemble = HedgeEnsemble.uniform(['model', 'fallback']);
      expect(
        ensemble.blend({'model': 0.8, 'fallback': 0.4}),
        closeTo(0.6, 1e-9),
      );
      expect(ensemble.blend({'model': 0.8}), closeTo(0.8, 1e-9));
    });

    test('rejects an empty membership', () {
      expect(() => HedgeEnsemble.uniform([]), throwsArgumentError);
    });

    test('survives a JSON round trip', () {
      final ensemble = HedgeEnsemble.uniform([
        'model',
        'fallback',
      ]).update({'model': 0.1, 'fallback': 0.5});
      final restored = HedgeEnsemble.fromJson(ensemble.toJson());
      expect(
        restored.weightOf('model'),
        closeTo(ensemble.weightOf('model'), 1e-12),
      );
      expect(restored.eta, ensemble.eta);
    });
  });

  group('PageHinkleyDetector', () {
    test('stays quiet on a stable loss stream', () {
      var detector = const PageHinkleyDetector();
      for (var index = 0; index < 200; index++) {
        detector = detector.observe(0.24);
      }
      expect(detector.alarm, isFalse);
    });

    test('alarms after a sustained deterioration', () {
      var detector = const PageHinkleyDetector();
      for (var index = 0; index < 60; index++) {
        detector = detector.observe(0.05);
      }
      for (var index = 0; index < 60; index++) {
        detector = detector.observe(0.85);
      }
      expect(detector.alarm, isTrue);
      expect(detector.statistic, greaterThan(detector.threshold));
    });

    test('needs a minimum sample before it can alarm', () {
      var detector = const PageHinkleyDetector();
      for (var index = 0; index < 5; index++) {
        detector = detector.observe(1.0);
      }
      expect(detector.alarm, isFalse);
    });

    test('reset forgets the excursion but keeps the configuration', () {
      var detector = const PageHinkleyDetector(delta: 0.01, threshold: 0.2);
      for (var index = 0; index < 40; index++) {
        detector = detector.observe(index < 20 ? 0.05 : 0.9);
      }
      final reset = detector.reset();
      expect(reset.alarm, isFalse);
      expect(reset.statistic, closeTo(0, 1e-12));
      expect(reset.delta, 0.01);
      expect(reset.threshold, 0.2);
    });

    test('survives a JSON round trip', () {
      final detector = const PageHinkleyDetector().observe(0.3).observe(0.4);
      final restored = PageHinkleyDetector.fromJson(detector.toJson());
      expect(restored.samples, detector.samples);
      expect(restored.statistic, closeTo(detector.statistic, 1e-12));
    });
  });

  group('CusumDetector', () {
    test('flags a challenger that keeps losing', () {
      var detector = const CusumDetector();
      for (var index = 0; index < 60; index++) {
        detector = detector.observe(0.02);
      }
      expect(detector.degraded, isTrue);
      expect(detector.improved, isFalse);
    });

    test('flags a challenger that keeps winning', () {
      var detector = const CusumDetector();
      for (var index = 0; index < 60; index++) {
        detector = detector.observe(-0.02);
      }
      expect(detector.improved, isTrue);
      expect(detector.degraded, isFalse);
    });

    test('ignores noise around zero', () {
      var detector = const CusumDetector();
      for (var index = 0; index < 200; index++) {
        detector = detector.observe(index.isEven ? 0.002 : -0.002);
      }
      expect(detector.degraded, isFalse);
      expect(detector.improved, isFalse);
    });

    test('survives a JSON round trip', () {
      final detector = const CusumDetector().observe(0.2).observe(-0.05);
      final restored = CusumDetector.fromJson(detector.toJson());
      expect(restored.positive, closeTo(detector.positive, 1e-12));
      expect(restored.negative, closeTo(detector.negative, 1e-12));
      expect(restored.samples, detector.samples);
    });
  });

  group('classifyEvent', () {
    test('a void match outranks every other signal', () {
      expect(
        classifyEvent(
          missingData: true,
          voided: true,
          marketShift: 0.9,
          driftAlarm: true,
        ),
        LearningEventKind.voidEvent,
      );
    });

    test('a broken feed is a data error, not drift', () {
      expect(
        classifyEvent(
          missingData: true,
          voided: false,
          marketShift: 0,
          driftAlarm: true,
        ),
        LearningEventKind.dataError,
      );
    });

    test('a large market move is recorded as its own kind', () {
      expect(
        classifyEvent(
          missingData: false,
          voided: false,
          marketShift: -0.4,
          driftAlarm: false,
        ),
        LearningEventKind.marketMove,
      );
    });

    test('a small market move is healthy', () {
      expect(
        classifyEvent(
          missingData: false,
          voided: false,
          marketShift: 0.05,
          driftAlarm: false,
        ),
        LearningEventKind.healthy,
      );
    });

    test('only healthy and market-move observations may teach', () {
      expect(LearningEventKind.healthy.learnable, isTrue);
      expect(LearningEventKind.marketMove.learnable, isTrue);
      expect(LearningEventKind.dataError.learnable, isFalse);
      expect(LearningEventKind.voidEvent.learnable, isFalse);
      expect(LearningEventKind.modelDrift.learnable, isFalse);
    });
  });

  group('OnlineLearner', () {
    test('learns nothing without observations', () {
      final state = const OnlineLearner().replay([]);
      expect(state.settledSamples, 0);
      expect(state.modelWeight, closeTo(0.5, 1e-9));
      expect(state.updatedAt, isNull);
    });

    test('prefers the member that keeps being right', () {
      final observations = [
        for (var day = 0; day < 80; day++)
          observation(
            day: day,
            outcome: day.isEven,
            model: day.isEven ? 0.86 : 0.14,
            fallback: 0.5,
          ),
      ];
      final state = const OnlineLearner().replay(observations);
      expect(state.settledSamples, 80);
      expect(state.modelWeight, greaterThan(0.6));
      expect(state.blendBrier, lessThan(0.25));
    });

    test('skips data errors and void events', () {
      final observations = [
        observation(day: 0, outcome: true, model: 0.7),
        observation(day: 1, outcome: true, model: 0.7, missingData: true),
        observation(day: 2, outcome: true, model: 0.7, voided: true),
        observation(day: 3, outcome: true, model: 0.7),
      ];
      final state = const OnlineLearner().replay(observations);
      expect(state.settledSamples, 2);
      expect(state.skipped['dataError'], 1);
      expect(state.skipped['voidEvent'], 1);
    });

    test('treats a non-finite forecast as a data error', () {
      final state = const OnlineLearner().replay([
        OnlineObservation(
          settledAt: DateTime.utc(2026, 1, 1),
          outcome: true,
          predictions: const {'model': double.nan, 'fallback': 0.5},
        ),
      ]);
      expect(state.settledSamples, 0);
      expect(state.skipped['dataError'], 1);
    });

    test('a market move still teaches but is labelled separately', () {
      final observations = [
        for (var day = 0; day < 6; day++)
          observation(day: day, outcome: true, model: 0.7),
        observation(day: 6, outcome: true, model: 0.7, marketShift: 0.42),
      ];
      final state = const OnlineLearner().replay(observations);
      expect(state.settledSamples, 7);
      expect(state.event, LearningEventKind.marketMove);
      expect(state.rollbacks, 0);
      expect(state.skipped, isEmpty);
    });

    test('rolls back when the blend keeps deteriorating', () {
      final observations = [
        for (var day = 0; day < 60; day++)
          observation(
            day: day,
            outcome: day.isEven,
            model: day.isEven ? 0.95 : 0.05,
          ),
        for (var day = 60; day < 160; day++)
          observation(
            day: day,
            outcome: day.isEven,
            model: day.isEven ? 0.05 : 0.95,
          ),
      ];
      final state = const OnlineLearner().replay(observations);
      expect(state.rollbacks, greaterThan(0));
      expect(state.version, greaterThan(1));
      expect(state.checkpoints, isNotEmpty);
    });

    test(
      'rollback restores a stored checkpoint rather than the latest weights',
      () {
        final observations = [
          for (var day = 0; day < 50; day++)
            observation(day: day, outcome: true, model: 0.95, fallback: 0.5),
          for (var day = 50; day < 140; day++)
            observation(day: day, outcome: false, model: 0.95, fallback: 0.5),
        ];
        final state = const OnlineLearner().replay(observations);
        expect(state.rollbacks, greaterThan(0));
        final checkpoint = state.checkpoints.last;
        expect(
          state.ensemble.weightOf('model'),
          closeTo(checkpoint.weights.weightOf('model'), 1e-12),
        );
      },
    );

    test('is independent of the order observations are supplied in', () {
      final observations = [
        for (var day = 0; day < 40; day++)
          observation(
            day: day,
            outcome: day % 3 != 0,
            model: day % 3 != 0 ? 0.74 : 0.26,
            fallback: 0.5,
          ),
      ];
      final forward = const OnlineLearner().replay(observations);
      final shuffled = const OnlineLearner().replay(
        observations.reversed.toList(),
      );
      expect(shuffled.modelWeight, closeTo(forward.modelWeight, 1e-12));
      expect(shuffled.blendBrier, closeTo(forward.blendBrier, 1e-12));
      expect(shuffled.settledSamples, forward.settledSamples);
    });

    test('the blend cannot fall far behind the best single member', () {
      final observations = [
        for (var day = 0; day < 120; day++)
          observation(
            day: day,
            outcome: day % 4 != 0,
            model: 0.75,
            fallback: 0.5,
          ),
      ];
      final state = const OnlineLearner().replay(observations);
      expect(state.blendBrier, lessThan(state.championBrier + 0.02));
    });

    test('state survives a JSON round trip', () {
      final state = const OnlineLearner().replay([
        for (var day = 0; day < 60; day++)
          observation(day: day, outcome: day.isEven, model: 0.6, fallback: 0.5),
      ]);
      final restored = OnlineLearningState.fromJson(state.toJson());
      expect(restored.version, state.version);
      expect(restored.settledSamples, state.settledSamples);
      expect(restored.modelWeight, closeTo(state.modelWeight, 1e-12));
      expect(restored.blendBrier, closeTo(state.blendBrier, 1e-12));
      expect(restored.event, state.event);
      expect(restored.checkpoints.length, state.checkpoints.length);
      expect(restored.updatedAt, state.updatedAt);
    });

    test('initial state is uniform and serialisable', () {
      final state = OnlineLearningState.initial(['model', 'fallback']);
      final restored = OnlineLearningState.fromJson(state.toJson());
      expect(restored.modelWeight, closeTo(0.5, 1e-12));
      expect(restored.drifting, isFalse);
    });
  });

  group('OnlineLearningService', () {
    final service = OnlineLearningService();

    test('only settled forecasts become observations', () {
      final observations = service.observations([
        shadow(day: 0, probability: 0.6, actual: 11),
        shadow(day: 1, probability: 0.6),
        shadow(day: 2, probability: 0.6, actual: 8),
      ]);
      expect(observations.length, 2);
      expect(observations.first.outcome, isTrue);
      expect(observations.last.outcome, isFalse);
    });

    test('the fallback only ever uses already settled matches', () {
      final observations = service.observations([
        shadow(day: 0, probability: 0.6, actual: 12),
        shadow(day: 1, probability: 0.6, actual: 13),
        shadow(day: 2, probability: 0.6, actual: 4),
      ]);
      expect(observations[0].predictions['fallback'], closeTo(0.5, 1e-9));
      expect(observations[1].predictions['fallback'], closeTo(1.0, 1e-9));
      expect(observations[2].predictions['fallback'], closeTo(1.0, 1e-9));
    });

    test('observations come out in settlement order', () {
      final observations = service.observations([
        shadow(day: 5, probability: 0.6, actual: 12),
        shadow(day: 1, probability: 0.6, actual: 4),
      ]);
      expect(
        observations.first.settledAt.isBefore(observations.last.settledAt),
        isTrue,
      );
    });

    test('an impossible corner count is marked as a data error', () {
      final observations = service.observations([
        shadow(day: 0, probability: 0.6, actual: 91),
      ]);
      expect(observations.single.missingData, isTrue);
    });

    test('a zero-corner match with a high expectation is treated as void', () {
      final observations = service.observations([
        shadow(day: 0, probability: 0.6, actual: 0, expected: 10.4),
      ]);
      expect(observations.single.voided, isTrue);
    });
  });
}
