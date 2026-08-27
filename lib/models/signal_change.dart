/// One reading of what a fixture card showed, kept so a pick that later turns
/// into 不建議 (or back) can be read as a series instead of a single state.
///
/// The card is recomputed on every refresh from the live HKJC price and the
/// current model, so the same fixture can move in and out of the recommendation
/// gate. Storing only the latest state answers "what does the model say now"
/// but not "why did it change", which is the question a reader actually has:
/// the price moved, the line moved, or the model's own probability moved.
class SignalChange {
  const SignalChange({
    required this.matchId,
    required this.leagueCode,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.matchDate,
    required this.capturedAt,
    required this.line,
    required this.direction,
    required this.odds,
    required this.modelProbability,
    required this.marketProbability,
    required this.edge,
    required this.requiredEdge,
    required this.recommended,
  });

  factory SignalChange.fromJson(Map<String, Object?> json) => SignalChange(
    matchId: json['matchId'] as String,
    leagueCode: json['leagueCode'] as String,
    leagueName: json['leagueName'] as String,
    homeTeam: json['homeTeam'] as String,
    awayTeam: json['awayTeam'] as String,
    matchDate: DateTime.parse(json['matchDate'] as String),
    capturedAt: DateTime.parse(json['capturedAt'] as String),
    line: (json['line'] as num).toDouble(),
    direction: json['direction'] as String,
    odds: (json['odds'] as num).toDouble(),
    modelProbability: (json['modelProbability'] as num).toDouble(),
    marketProbability: (json['marketProbability'] as num).toDouble(),
    edge: (json['edge'] as num).toDouble(),
    requiredEdge: (json['requiredEdge'] as num).toDouble(),
    recommended: json['recommended'] as bool,
  );

  final String matchId;
  final String leagueCode;
  final String leagueName;

  /// Chinese names as HKJC published them, so the log reads like the card.
  final String homeTeam;
  final String awayTeam;
  final DateTime matchDate;

  /// When this reading was taken.
  final DateTime capturedAt;
  final double line;

  /// `high` or `low`: the side shown, recommended or merely observed.
  final String direction;
  final double odds;
  final double modelProbability;

  /// Margin-free market probability of the same side at [capturedAt].
  final double marketProbability;

  /// Expected value per unit stake at [odds].
  final double edge;

  /// Expected value the side had to clear to be recommended.
  final double requiredEdge;
  final bool recommended;

  String get directionLabel => direction == 'high' ? '大' : '細';

  Map<String, Object?> toJson() => {
    'matchId': matchId,
    'leagueCode': leagueCode,
    'leagueName': leagueName,
    'homeTeam': homeTeam,
    'awayTeam': awayTeam,
    'matchDate': matchDate.toIso8601String(),
    'capturedAt': capturedAt.toIso8601String(),
    'line': line,
    'direction': direction,
    'odds': odds,
    'modelProbability': modelProbability,
    'marketProbability': marketProbability,
    'edge': edge,
    'requiredEdge': requiredEdge,
    'recommended': recommended,
  };
}
