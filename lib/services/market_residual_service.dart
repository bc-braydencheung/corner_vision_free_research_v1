import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shadow_forecast.dart';
import 'market_residual.dart';
import 'online_learning_service.dart';

/// Fits and stores the market-residual correction from settled forecasts.
///
/// Only records that carried a usable free quote at capture time take part, so
/// the correction is measured against the price it is supposed to beat and
/// never against a reconstructed one.
///
/// The model side of every observation is the stored pre-residual probability,
/// which is exactly the input the correction is applied to in production. The
/// displayed probability would be the correction's own output on every record
/// captured after adoption, so fitting on it would let the correction train on
/// itself.
class MarketResidualService {
  MarketResidualService({this.learner = const MarketResidualLearner()});

  static const _storageKey = 'edgewise_market_residual_v1';

  final MarketResidualLearner learner;

  Future<MarketResidualState> update(List<ShadowForecast> records) async {
    final state = learner.fit(observations(records));
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey, jsonEncode(state.toJson()));
    return state;
  }

  Future<MarketResidualState> load() async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_storageKey);
    if (encoded == null) {
      return MarketResidualState.initial;
    }
    try {
      return MarketResidualState.fromJson(
        (jsonDecode(encoded) as Map).cast<String, Object?>(),
      );
    } on Object {
      return MarketResidualState.initial;
    }
  }

  List<MarketResidualObservation> observations(
    List<ShadowForecast> records,
  ) => [
    for (final record in records)
      if (record.actualTotalCorners != null &&
          record.settledAt != null &&
          record.marketOverProbability != null &&
          record.over9_5Probability != null &&
          record.actualTotalCorners! >= 0 &&
          record.actualTotalCorners! <= 40)
        MarketResidualObservation(
          settledAt: record.settledAt!,
          outcome: record.actualTotalCorners! > OnlineLearningService.overLine,
          modelProbability:
              record.calibratedOver9_5Probability ?? record.over9_5Probability!,
          marketProbability: record.marketOverProbability!,
        ),
  ];
}
