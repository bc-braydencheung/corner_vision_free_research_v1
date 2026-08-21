import 'simulated_trade.dart';

/// The pick a card is offering to the simulated account, before a stake.
///
/// Football corners and racing win pools reach the same stake sheet, so both
/// describe the selection through this one shape. Every figure is copied from
/// the assessment the card already showed — nothing is recomputed here, so the
/// ledger records the price and probability the user actually saw.
class SimulationDraft {
  const SimulationDraft({
    required this.sport,
    required this.marketType,
    required this.matchId,
    required this.leagueCode,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.startTime,
    required this.selectionLabel,
    required this.direction,
    required this.line,
    required this.odds,
    required this.modelProbability,
    required this.marketProbability,
    required this.edge,
    required this.confidence,
    required this.confidenceLabel,
    required this.recommended,
    this.selectionId,
    this.placeSlots,
    this.pushProbability = 0,
    this.stakeFraction = 0,
    this.marketSource = '',
    this.marketCapturedAt,
  });

  /// `football` or `racing`.
  final String sport;

  /// `corners`, `win` or `place`.
  final String marketType;

  /// HKJC match id, or the race id.
  final String matchId;
  final String leagueCode;
  final String leagueName;

  /// Home club, or the horse for a racing pick.
  final String homeTeam;

  /// Away club, or the venue and race number for a racing pick.
  final String awayTeam;
  final DateTime startTime;

  /// What the card printed, e.g. `角球 9.5 大` or `獨贏 7 號`.
  final String selectionLabel;

  /// `over`, `under` or `win`; the side the ledger settles on.
  final String direction;

  /// Corner line of the pick; 0 for a racing pool.
  final double line;

  /// HKJC price the pick was read at.
  final double odds;
  final double modelProbability;

  /// Vig-free market probability of the same side.
  final double marketProbability;
  final double edge;
  final double confidence;
  final String confidenceLabel;

  /// Whether the model gate passed; an observation is recorded as such.
  final bool recommended;
  final String? selectionId;
  final int? placeSlots;
  final double pushProbability;

  /// Fraction of the account a quarter-Kelly stake would be, when priced.
  final double stakeFraction;
  final String marketSource;
  final DateTime? marketCapturedAt;

  String get subject =>
      sport == 'racing' ? '$homeTeam · $awayTeam' : '$homeTeam 對 $awayTeam';

  /// Vig-free price of the same side, the market's own view of the pick.
  double get fairOdds => marketProbability <= 0 ? 0 : 1 / marketProbability;

  /// Price the model itself would quote for the side.
  double get modelOdds => modelProbability <= 0 ? 0 : 1 / modelProbability;

  /// The ledger row this pick becomes once a stake is entered.
  SimulatedTrade toTrade({required double stake, required DateTime now}) {
    return SimulatedTrade(
      id: '$matchId-${direction}_$line-${now.microsecondsSinceEpoch}',
      matchId: matchId,
      leagueCode: leagueCode,
      leagueName: leagueName,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      matchDate: startTime,
      createdAt: now,
      direction: direction,
      line: line,
      odds: odds,
      stake: stake,
      modelWinProbability: modelProbability,
      modelPushProbability: pushProbability,
      expectedValue: edge,
      confidence: confidenceLabel,
      status: 'open',
      actualTotalCorners: null,
      profit: null,
      sport: sport,
      marketType: marketType,
      selectionId: selectionId,
      placeSlots: placeSlots,
      stakeStrategy: 'manual',
      marketSource: marketSource,
      marketCapturedAt: marketCapturedAt,
      recommended: recommended,
      selectionLabel: selectionLabel,
      marketProbability: marketProbability,
    );
  }
}
