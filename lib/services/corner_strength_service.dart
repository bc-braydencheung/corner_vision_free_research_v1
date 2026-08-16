import '../models/football_mobile.dart';
import 'corner_strength_model.dart';
import 'football_store.dart';
import 'two_stage_corner_model.dart';

/// Both corner priors of every league, fitted from the same stored history.
class CornerPriorTables {
  const CornerPriorTables({required this.strengths, required this.shots});

  static const empty = CornerPriorTables(strengths: {}, shots: {});

  /// Direct corner-count Kalman fit, keyed by league code.
  final Map<String, CornerStrengthTable> strengths;

  /// Two-stage shots/conversion/referee fit, keyed by league code.
  final Map<String, ShotCornerTable> shots;
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
    final fitted = fit(dataset);
    _cache = fitted;
    return fitted;
  }

  CornerPriorTables fit(MobileFootballDataset dataset) => CornerPriorTables(
    strengths: {
      for (final league in dataset.leagues)
        league.code: _model.fit(dataset.rows, league),
    },
    shots: {
      for (final league in dataset.leagues)
        league.code: _twoStage.fit(dataset.rows, league),
    },
  );
}
