import '../models/simulated_trade.dart';
import '../models/simulation_draft.dart';
import 'hkjc_corner_model.dart';

/// What the simulated account already holds, so a card can say so before the
/// same pick is recorded twice.
///
/// Pairing is by explicit HKJC id plus the market, side and line the ledger
/// stored, never by team or horse name: a fixture whose line moved is a
/// different selection and must stay recordable.
class StakedSelections {
  const StakedSelections({this.selections = const {}, this.matches = const {}});

  /// Reads the keys of [trades]; settled rows count too, since a graded bet is
  /// still one the user placed on that fixture.
  factory StakedSelections.of(List<SimulatedTrade> trades) {
    final selections = <String>{};
    final matches = <String>{};
    for (final trade in trades) {
      selections.add(
        _key(
          matchId: trade.matchId,
          marketType: trade.marketType,
          direction: trade.direction,
          line: trade.line,
          selectionId: trade.selectionId,
        ),
      );
      matches.add(trade.matchId);
    }
    return StakedSelections(selections: selections, matches: matches);
  }

  static const empty = StakedSelections();

  /// Market/side/line keys of every recorded bet.
  final Set<String> selections;

  /// HKJC match or race ids carrying at least one recorded bet.
  final Set<String> matches;

  /// Whether this exact selection has already been recorded.
  bool holdsDraft(SimulationDraft draft) => selections.contains(
    _key(
      matchId: draft.matchId,
      marketType: draft.marketType,
      direction: draft.direction,
      line: draft.line,
      selectionId: draft.selectionId,
    ),
  );

  /// Whether the corner side a fixture card is offering is already recorded.
  bool holdsCornerPick({
    required String matchId,
    required HkjcCornerRecommendation pick,
  }) => selections.contains(
    _key(
      matchId: matchId,
      marketType: 'corners',
      direction: pick.direction == 'high' ? 'over' : 'under',
      line: pick.line.line.line,
    ),
  );

  /// Whether this fixture or race carries any recorded bet at all.
  bool holdsMatch(String matchId) => matches.contains(matchId);

  static String _key({
    required String matchId,
    required String marketType,
    required String direction,
    required double line,
    String? selectionId,
  }) =>
      '$matchId|$marketType|$direction|${line.toStringAsFixed(2)}'
      '|${selectionId ?? ''}';
}
