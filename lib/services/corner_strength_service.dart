import 'dart:isolate';

import '../models/football_mobile.dart';
import 'bivariate_corner_model.dart';
import 'corner_strength_model.dart';
import 'football_store.dart';
import 'two_stage_corner_model.dart';

/// Both corner priors of every league, fitted from the same stored history.
class CornerPriorTables {
  const CornerPriorTables({
    required this.strengths,
    required this.shots,
    this.joint = const {},
  });

  static const empty = CornerPriorTables(strengths: {}, shots: {});

  /// Direct corner-count Kalman fit, keyed by league code.
  final Map<String, CornerStrengthTable> strengths;

  /// Two-stage shots/conversion/referee fit, keyed by league code.
  final Map<String, ShotCornerTable> shots;

  /// Measured home/away corner covariance, keyed by league code.
  final Map<String, BivariateCornerFit> joint;
}

/// Fits one [CornerStrengthTable] and one [ShotCornerTable] per league from the
/// locally stored history.
///
/// The free football-data history is no longer displayed as fixtures, but it is
/// still the only free source of completed corner counts, shot counts and match
/// officials, so it is what both priors behind the HKJC corner market are
/// trained on.
class CornerStrengthService {
  CornerStrengthService({
    FootballStore? store,
    CornerStrengthModel? model,
    TwoStageCornerModel? twoStage,
  }) : _store = store ?? FootballStore(),
       _model = model ?? const CornerStrengthModel(),
       _twoStage = twoStage ?? const TwoStageCornerModel();

  final FootballStore _store;
  final CornerStrengthModel _model;
  final TwoStageCornerModel _twoStage;

  CornerPriorTables? _cache;

  /// Tables keyed by league code, refitted only when [force] is set.
  Future<CornerPriorTables> tables({bool force = false}) async {
    final cached = _cache;
    if (cached != null && !force) {
      return cached;
    }
    final MobileFootballDataset dataset;
    try {
      dataset = await _store.loadDataset();
    } on Object {
      return CornerPriorTables.empty;
    }
    final model = _model;
    final twoStage = _twoStage;
    // Both fits sweep the whole free history, so they run off the UI isolate.
    final fitted = await Isolate.run(() => _fitOff(dataset, model, twoStage));
    _cache = fitted;
    return fitted;
  }

  CornerPriorTables fit(MobileFootballDataset dataset) =>
      _fitOff(dataset, _model, _twoStage);

  static CornerPriorTables _fitOff(
    MobileFootballDataset dataset,
    CornerStrengthModel model,
    TwoStageCornerModel twoStage,
  ) => CornerPriorTables(
    joint: {
      for (final league in dataset.leagues)
        league.code: const BivariateCornerModel().fit(dataset.rows, league),
    },
    strengths: {
      for (final league in dataset.leagues)
        league.code: model.fit(dataset.rows, league),
    },
    shots: {
      for (final league in dataset.leagues)
        league.code: twoStage.fit(dataset.rows, league),
    },
  );
}
