import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shadow_forecast.dart';
import 'online_learning.dart';

/// Replays the settled shadow forecasts into an online learning state.
///
/// The two competing members are the fitted model and a fallback that only
/// knows how often the line has gone over so far. Both are scored on the same
/// settled matches, in settlement order, and the fallback's forecast for a match
/// only uses matches that had already settled before it, so the comparison
/// carries no hindsight.
class OnlineLearningService {
  OnlineLearningService({this.learner = const OnlineLearner()});

  static const _storageKey = 'edgewise_online_learning_v1';
  static const overLine = 9.5;

  final OnlineLearner learner;

  /// Recomputes the state from [records] and stores it.
  Future<OnlineLearningState> update(List<ShadowForecast> records) async {
    final state = learner.replay(observations(records));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(state.toJson()));
    return state;
  }

  /// Last stored state, or a fresh one when nothing has been stored yet.
  Future<OnlineLearningState> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return OnlineLearningState.initial(learner.members);
    }
    try {
      return OnlineLearningState.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    } on Object {
      return OnlineLearningState.initial(learner.members);
    }
  }

  /// Turns settled shadow forecasts into learner observations.
  List<OnlineObservation> observations(List<ShadowForecast> records) {
    final settled =
        records
            .where(
              (record) =>
                  record.actualTotalCorners != null && record.settledAt != null,
            )
            .toList()
          ..sort((left, right) => left.settledAt!.compareTo(right.settledAt!));
    final observations = <OnlineObservation>[];
    var overs = 0;
    var seen = 0;
    for (final record in settled) {
      final actual = record.actualTotalCorners!;
      final outcome = actual > overLine;
      // Until anything has settled the fallback can only claim a coin flip.
      final fallback = seen == 0 ? 0.5 : overs / seen;
      observations.add(
        OnlineObservation(
          settledAt: record.settledAt!,
          outcome: outcome,
          predictions: {
            'model': record.over9_5Probability,
            'fallback': fallback,
          },
          // A negative or absurd corner count is a broken feed, not a result.
          missingData: actual < 0 || actual > 40,
          voided: actual == 0 && record.expectedTotalCorners > 6,
        ),
      );
      seen += 1;
      if (outcome) {
        overs += 1;
      }
    }
    return observations;
  }
}
