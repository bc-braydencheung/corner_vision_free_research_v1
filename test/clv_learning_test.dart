import 'package:edgewise/models/football_mobile.dart';
import 'package:edgewise/models/shadow_forecast.dart';
import 'package:edgewise/services/clv_learning.dart';
import 'package:edgewise/services/market_timeline.dart';
import 'package:edgewise/services/online_learning.dart';
import 'package:flutter_test/flutter_test.dart';

final _kickOff = DateTime.utc(2026, 8, 10, 19);

FootballOddsSnapshot _quote({
  required DateTime capturedAt,
  required double over,
  required double under,
  double line = 9.5,
  String matchId = 'FB1',
  bool inPlay = false,
}) => FootballOddsSnapshot(
  matchId: matchId,
  capturedAt: capturedAt,
  source: 'hkjc-chl',
  line: line,
  overOdds: over,
  underOdds: under,
  inPlay: inPlay,
);

ShadowForecast _forecast({
  required DateTime capturedAt,
  double overProbability = 0.6,
  double? marketOverProbability,
  String matchId = 'FB1',
  DateTime? matchDate,
}) => ShadowForecast(
  id: '$matchId-${capturedAt.toIso8601String()}',
  matchId: matchId,
  leagueCode: 'E0',
  leagueName: '英超',
  homeTeam: '阿仙奴',
  awayTeam: '利物浦',
  matchDate: matchDate ?? _kickOff,
  capturedAt: capturedAt,
  modelVersion: 'test',
  expectedTotalCorners: 10.2,
  over9_5Probability: overProbability,
  referenceMae: 2.6,
  referenceBrier: 0.25,
  marketOverProbability: marketOverProbability,
);

void main() {
  group('closing-line learning set', () {
    test('grades a forecast against the last pre-kick-off quote', () {
      final set = closingLineLearningSet(
        forecasts: [
          _forecast(capturedAt: _kickOff.subtract(const Duration(hours: 6))),
        ],
        stored: [
          _quote(
            capturedAt: _kickOff.subtract(const Duration(hours: 20)),
            over: 2.0,
            under: 1.9,
          ),
          _quote(
            capturedAt: _kickOff.subtract(const Duration(minutes: 10)),
            over: 1.7,
            under: 2.2,
          ),
          // Anything captured after the start is never a closing quote.
          _quote(
            capturedAt: _kickOff.add(const Duration(minutes: 20)),
            over: 1.2,
            under: 4.0,
            inPlay: true,
          ),
        ],
        asOf: _kickOff.add(const Duration(hours: 3)),
      );

      expect(set.graded, 1);
      final observation = set.observations.single;
      expect(observation.fromClosingLine, isTrue);
      expect(observation.settledAt, _kickOff);
      final closingFair = twoWayFairProbabilities(1.7, 2.2)!.over;
      expect(observation.target, closeTo(closingFair, 1e-9));
      expect(observation.predictions['model'], 0.6);
      // Without a stored capture-time market probability the opening line is
      // the baseline the model has to beat.
      final openingFair = twoWayFairProbabilities(2.0, 1.9)!.over;
      expect(observation.predictions['fallback'], closeTo(openingFair, 1e-9));
      expect(observation.marketShift, closeTo(closingFair - openingFair, 1e-9));
    });

    test(
      'uses the market probability held at capture time as the baseline',
      () {
        final set = closingLineLearningSet(
          forecasts: [
            _forecast(
              capturedAt: _kickOff.subtract(const Duration(hours: 6)),
              marketOverProbability: 0.44,
            ),
          ],
          stored: [
            _quote(
              capturedAt: _kickOff.subtract(const Duration(hours: 20)),
              over: 2.0,
              under: 1.9,
            ),
            _quote(
              capturedAt: _kickOff.subtract(const Duration(minutes: 10)),
              over: 1.7,
              under: 2.2,
            ),
          ],
          asOf: _kickOff.add(const Duration(hours: 3)),
        );

        expect(set.observations.single.predictions['fallback'], 0.44);
      },
    );

    test('refuses a fixture whose kick-off has not passed', () {
      final set = closingLineLearningSet(
        forecasts: [
          _forecast(capturedAt: _kickOff.subtract(const Duration(hours: 6))),
        ],
        stored: [
          _quote(
            capturedAt: _kickOff.subtract(const Duration(hours: 20)),
            over: 2.0,
            under: 1.9,
          ),
          _quote(
            capturedAt: _kickOff.subtract(const Duration(hours: 1)),
            over: 1.7,
            under: 2.2,
          ),
        ],
        asOf: _kickOff.subtract(const Duration(minutes: 30)),
      );

      expect(set.graded, 0);
      expect(set.skipped[ClosingLineSkip.kickOffPending], 1);
      expect(set.considered, 1);
    });

    test('refuses a closing quote the forecast had already seen', () {
      final set = closingLineLearningSet(
        forecasts: [
          _forecast(capturedAt: _kickOff.subtract(const Duration(minutes: 5))),
        ],
        stored: [
          _quote(
            capturedAt: _kickOff.subtract(const Duration(hours: 20)),
            over: 2.0,
            under: 1.9,
          ),
          _quote(
            capturedAt: _kickOff.subtract(const Duration(minutes: 30)),
            over: 1.7,
            under: 2.2,
          ),
        ],
        asOf: _kickOff.add(const Duration(hours: 3)),
      );

      expect(set.graded, 0);
      expect(set.skipped[ClosingLineSkip.closingNotAfterForecast], 1);
    });

    test('refuses a line that never moved and a fixture with no history', () {
      final single = closingLineLearningSet(
        forecasts: [
          _forecast(capturedAt: _kickOff.subtract(const Duration(hours: 6))),
        ],
        stored: [
          _quote(
            capturedAt: _kickOff.subtract(const Duration(hours: 2)),
            over: 1.9,
            under: 1.9,
          ),
        ],
        asOf: _kickOff.add(const Duration(hours: 3)),
      );
      expect(single.skipped[ClosingLineSkip.lineNeverMoved], 1);

      final none = closingLineLearningSet(
        forecasts: [
          _forecast(capturedAt: _kickOff.subtract(const Duration(hours: 6))),
        ],
        stored: const [],
        asOf: _kickOff.add(const Duration(hours: 3)),
      );
      expect(none.skipped[ClosingLineSkip.noTimeline], 1);
    });

    test('ignores quotes recorded on another line', () {
      final set = closingLineLearningSet(
        forecasts: [
          _forecast(capturedAt: _kickOff.subtract(const Duration(hours: 6))),
        ],
        stored: [
          _quote(
            capturedAt: _kickOff.subtract(const Duration(hours: 20)),
            over: 2.0,
            under: 1.9,
            line: 11.5,
          ),
          _quote(
            capturedAt: _kickOff.subtract(const Duration(minutes: 10)),
            over: 1.7,
            under: 2.2,
            line: 11.5,
          ),
        ],
        asOf: _kickOff.add(const Duration(hours: 3)),
      );

      expect(set.skipped[ClosingLineSkip.noTimeline], 1);
    });
  });

  group('learner with closing-line labels', () {
    test('scores a probability target and counts both label kinds', () {
      final state = const OnlineLearner(checkpointEvery: 2).replay([
        OnlineObservation.closingLine(
          settledAt: DateTime.utc(2026, 8, 1),
          target: 0.6,
          predictions: const {'model': 0.6, 'fallback': 0.4},
        ),
        OnlineObservation(
          settledAt: DateTime.utc(2026, 8, 2),
          outcome: true,
          predictions: const {'model': 0.7, 'fallback': 0.5},
        ),
      ]);

      expect(state.settledSamples, 2);
      expect(state.closingLineSamples, 1);
      expect(state.resultSamples, 1);
      // The model matched the closing line exactly, so it must end up ahead of
      // the fallback.
      expect(state.modelWeight, greaterThan(0.5));
    });

    test('squared loss reduces to the Brier score on a binary label', () {
      expect(squaredLoss(0.3, 1), closeTo(brierLoss(0.3, true), 1e-12));
      expect(squaredLoss(0.3, 0), closeTo(brierLoss(0.3, false), 1e-12));
    });

    test('a closing-line observation keeps its probability target in json', () {
      final state = const OnlineLearner().replay([
        OnlineObservation.closingLine(
          settledAt: DateTime.utc(2026, 8, 1),
          target: 0.55,
          predictions: const {'model': 0.5, 'fallback': 0.5},
        ),
      ]);
      final restored = OnlineLearningState.fromJson(state.toJson());
      expect(restored.closingLineSamples, 1);
      expect(restored.resultSamples, 0);
    });
  });
}
