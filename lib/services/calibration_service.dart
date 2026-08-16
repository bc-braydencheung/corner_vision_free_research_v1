import 'dart:convert';
import 'dart:math';

import '../models/racing_mobile.dart';
import '../models/shadow_forecast.dart';
import 'calibration.dart';
import 'racing_store.dart';

/// Calibration of one market, ready to be displayed and applied.
class MarketCalibration {
  const MarketCalibration({
    required this.market,
    required this.calibrator,
    required this.report,
  });

  static MarketCalibration none(String market) => MarketCalibration(
    market: market,
    calibrator: const IdentityCalibrator(),
    report: CalibrationReport.empty,
  );

  /// Human readable market name, e.g. `角球大 9.5`.
  final String market;
  final ProbabilityCalibrator calibrator;
  final CalibrationReport report;

  /// Calibrated probability, or the raw score while the sample is too small.
  double apply(double probability) => calibrator.reliable
      ? calibrator.apply(probability)
      : probability.clamp(0.0, 1.0);
}

/// Calibration state of every market the app publishes probabilities for.
class CalibrationState {
  const CalibrationState({
    required this.footballCorners,
    required this.racingWin,
    required this.racingPlace,
  });

  static final empty = CalibrationState(
    footballCorners: MarketCalibration.none('角球大細 9.5'),
    racingWin: MarketCalibration.none('賽馬獨贏'),
    racingPlace: MarketCalibration.none('賽馬位置'),
  );

  final MarketCalibration footballCorners;
  final MarketCalibration racingWin;
  final MarketCalibration racingPlace;

  List<MarketCalibration> get markets => [
    footballCorners,
    racingWin,
    racingPlace,
  ];

  bool get anyReliable =>
      markets.any((calibration) => calibration.calibrator.reliable);
}

/// Fits and scores one calibrator per market on settled outcomes only.
///
/// Football corner samples come from the shadow forecast log, which records the
/// probability before kick-off and settles it against the real corner count;
/// racing samples come from the stored dataset rows that the active model was
/// not trained on. Nothing here touches unsettled predictions, so a market can
/// never calibrate itself on its own forecast.
class CalibrationService {
  CalibrationService({RacingStore? racingStore, this.windowSize = 400})
    : racingStore = racingStore ?? RacingStore();

  final RacingStore racingStore;

  /// Number of most recent settled outcomes used per market.
  final int windowSize;

  /// Corner-market samples of the `over 9.5` line, oldest first.
  List<CalibrationSample> footballSamples(List<ShadowForecast> records) => [
    for (final record in records)
      if (record.actualTotalCorners != null)
        CalibrationSample(
          probability: record.over9_5Probability,
          outcome: record.actualTotalCorners! > 9.5,
          observedAt: record.settledAt ?? record.matchDate,
        ),
  ];

  /// Win and place samples of the races the active model held out.
  ({List<CalibrationSample> win, List<CalibrationSample> place}) racingSamples({
    required MobileRacingDataset dataset,
    required MobileRacingModel? model,
  }) {
    if (model == null || !model.useWinModel) {
      return (win: const [], place: const []);
    }
    final trainedThrough = DateTime.tryParse(model.trainedThrough);
    final byRace = <String, List<RacingTrainingRow>>{};
    for (final row in dataset.rows) {
      final date = DateTime.tryParse(row.date);
      if (trainedThrough != null &&
          date != null &&
          !date.isAfter(trainedThrough)) {
        continue;
      }
      byRace.putIfAbsent(row.raceId, () => <RacingTrainingRow>[]).add(row);
    }
    final win = <CalibrationSample>[];
    final place = <CalibrationSample>[];
    for (final race in byRace.entries) {
      final rows = race.value;
      if (rows.length < 2) {
        continue;
      }
      final observedAt = DateTime.tryParse(rows.first.date);
      final winScores = [
        for (final row in rows)
          _sigmoid(_dot(model.winWeights, row.features) + model.winIntercept),
      ];
      final winTotal = winScores.fold<double>(0, (sum, value) => sum + value);
      if (winTotal <= 0) {
        continue;
      }
      for (var index = 0; index < rows.length; index++) {
        win.add(
          CalibrationSample(
            probability: winScores[index] / winTotal,
            outcome: rows[index].won == 1,
            observedAt: observedAt,
          ),
        );
      }
      if (!model.usePlaceModel) {
        continue;
      }
      final slots = rows.length >= 7
          ? 3.0
          : rows.length >= 4
          ? 2.0
          : 0.0;
      if (slots == 0) {
        continue;
      }
      final placeScores = [
        for (final row in rows)
          _sigmoid(
            _dot(model.placeWeights, row.features) + model.placeIntercept,
          ),
      ];
      final placeTotal = placeScores.fold<double>(
        0,
        (sum, value) => sum + value,
      );
      if (placeTotal <= 0) {
        continue;
      }
      for (var index = 0; index < rows.length; index++) {
        place.add(
          CalibrationSample(
            probability: (placeScores[index] / placeTotal * slots).clamp(
              0.0,
              1.0,
            ),
            outcome: rows[index].placed == 1,
            observedAt: observedAt,
          ),
        );
      }
    }
    return (win: win, place: place);
  }

  /// Fits every market on its own rolling window of settled outcomes.
  Future<CalibrationState> evaluate(List<ShadowForecast> shadowRecords) async {
    final football = _market(
      '角球大細 9.5',
      rollingWindow(footballSamples(shadowRecords), size: windowSize),
    );
    MarketCalibration win = MarketCalibration.none('賽馬獨贏');
    MarketCalibration place = MarketCalibration.none('賽馬位置');
    try {
      final dataset = await racingStore.loadDataset();
      final model = await racingStore.loadModel();
      final samples = racingSamples(dataset: dataset, model: model);
      win = _market('賽馬獨贏', rollingWindow(samples.win, size: windowSize));
      place = _market('賽馬位置', rollingWindow(samples.place, size: windowSize));
    } on Object {
      // A missing or unreadable dataset simply leaves racing uncalibrated.
    }
    return CalibrationState(
      footballCorners: football,
      racingWin: win,
      racingPlace: place,
    );
  }

  MarketCalibration _market(String market, List<CalibrationSample> samples) {
    final calibrator = fitCalibrator(samples);
    return MarketCalibration(
      market: market,
      calibrator: calibrator,
      report: evaluateCalibration(samples, calibrator: calibrator),
    );
  }

  static double _dot(List<double> weights, List<double> features) {
    var total = 0.0;
    final length = min(weights.length, features.length);
    for (var index = 0; index < length; index++) {
      total += weights[index] * features[index];
    }
    return total;
  }

  static double _sigmoid(double value) => 1 / (1 + exp(-value.clamp(-30, 30)));

  /// Serialises a report so it can be included in the research export.
  static Map<String, Object?> reportJson(MarketCalibration calibration) => {
    'market': calibration.market,
    'method': calibration.report.method,
    'samples': calibration.report.samples,
    'baseRate': calibration.report.baseRate,
    'brier': calibration.report.brier,
    'baselineBrier': calibration.report.baselineBrier,
    'brierSkill': calibration.report.brierSkill,
    'expectedCalibrationError': calibration.report.expectedCalibrationError,
    'maximumCalibrationError': calibration.report.maximumCalibrationError,
    'windowStart': calibration.report.windowStart?.toIso8601String(),
    'windowEnd': calibration.report.windowEnd?.toIso8601String(),
  };

  static String encodeReports(CalibrationState state) => jsonEncode({
    'schemaVersion': 1,
    'markets': [for (final market in state.markets) reportJson(market)],
  });
}
