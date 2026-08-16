import '../models/football_mobile.dart';
import 'corner_strength_model.dart';
import 'football_store.dart';

/// Fits one [CornerStrengthTable] per league from the locally stored history.
///
/// The free football-data history is no longer displayed as fixtures, but it is
/// still the only free source of completed corner counts, so it is what the
/// team-strength prior behind the HKJC corner market is trained on.
class CornerStrengthService {
  CornerStrengthService({FootballStore? store, CornerStrengthModel? model})
    : _store = store ?? FootballStore(),
      _model = model ?? const CornerStrengthModel();

  final FootballStore _store;
  final CornerStrengthModel _model;

  Map<String, CornerStrengthTable>? _cache;

  /// Tables keyed by league code, refitted only when [force] is set.
  Future<Map<String, CornerStrengthTable>> tables({bool force = false}) async {
    final cached = _cache;
    if (cached != null && !force) {
      return cached;
    }
    final MobileFootballDataset dataset;
    try {
      dataset = await _store.loadDataset();
    } on Object {
      return const {};
    }
    final fitted = fit(dataset);
    _cache = fitted;
    return fitted;
  }

  Map<String, CornerStrengthTable> fit(MobileFootballDataset dataset) => {
    for (final league in dataset.leagues)
      league.code: _model.fit(dataset.rows, league),
  };
}
