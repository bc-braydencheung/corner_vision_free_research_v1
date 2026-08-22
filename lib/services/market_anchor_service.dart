import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shadow_forecast.dart';
import 'market_anchor.dart';
import 'online_learning_service.dart';

/// Learns and stores the market anchor from the settled shadow forecasts.
///
/// Only records that carried a usable pair of free market prices take part, so
/// the anchor is measured against the price it anchors to and never against a
/// reconstructed one.
///
/// The model side of every observation is the stored pre-shrinkage probability,
/// which is exactly what the anchor pulls towards the market in production.
/// The displayed probability has the previously learned anchor already inside
/// it, so fitting on it would shrink the model towards the market again on
/// every refit.
class MarketAnchorService {
  MarketAnchorService({this.learner = const MarketAnchorLearner()});

  static const _storageKey = 'edgewise_market_anchor_v1';

  final MarketAnchorLearner learner;

  Future<MarketAnchorState> update(List<ShadowForecast> records) async {
    final state = learner.replay(observations(records));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(state.toJson()));
    return state;
  }

  Future<MarketAnchorState> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return MarketAnchorState.initial;
    }
    try {
      return MarketAnchorState.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    } on Object {
      return MarketAnchorState.initial;
    }
  }

  List<MarketAnchorObservation> observations(List<ShadowForecast> records) => [
    for (final record in records)
      if (record.actualTotalCorners != null &&
          record.settledAt != null &&
          record.marketOverProbability != null &&
          record.over9_5Probability != null &&
          record.actualTotalCorners! >= 0 &&
          record.actualTotalCorners! <= 40)
        MarketAnchorObservation(
          settledAt: record.settledAt!,
          outcome: record.actualTotalCorners! > OnlineLearningService.overLine,
          modelProbability:
              record.calibratedOver9_5Probability ?? record.over9_5Probability!,
          marketProbability: record.marketOverProbability!,
        ),
  ];
}
