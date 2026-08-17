import '../core/combinatorics.dart';

/// Parimutuel arithmetic for the first division.
///
/// `E[return | c] = P(win) * Pool / (1 + N q(c)) - stake`
///
/// `P(win) = 1 / C(49,6)` is the same for every combination. Only the expected
/// number of co-winners `N q(c)` changes, and only that is worth optimising.
class ParimutuelOutcome {
  const ParimutuelOutcome({
    required this.winProbability,
    required this.expectedCoWinners,
    required this.expectedPayoutIfWon,
    required this.expectedReturn,
    required this.expectedValueRatio,
    required this.baselineExpectedReturn,
    required this.improvementRatio,
  });

  final double winProbability;
  final double expectedCoWinners;
  final double expectedPayoutIfWon;
  final double expectedReturn;

  /// `E[return] / stake`; always negative for a real lottery.
  final double expectedValueRatio;

  final double baselineExpectedReturn;

  /// How much better than an average-popularity combination, in expected value
  /// of the first-division component.
  final double improvementRatio;
}

ParimutuelOutcome evaluateParimutuel({
  required double pool,
  required double unitsSold,
  required double crowdRatio,
  double stake = 10.0,
}) {
  final p = 1 / kTotalCombinations;
  final qUniform = 1 / kTotalCombinations;
  final coWinners = unitsSold * qUniform * crowdRatio;
  final baselineCoWinners = unitsSold * qUniform;

  final payout = pool / (1 + coWinners);
  final baselinePayout = pool / (1 + baselineCoWinners);

  final expected = p * payout;
  final baselineExpected = p * baselinePayout;

  return ParimutuelOutcome(
    winProbability: p,
    expectedCoWinners: coWinners,
    expectedPayoutIfWon: payout,
    expectedReturn: expected - stake,
    expectedValueRatio: (expected - stake) / stake,
    baselineExpectedReturn: baselineExpected - stake,
    improvementRatio: baselineExpected == 0 ? 1 : expected / baselineExpected,
  );
}

/// Kelly fraction for a single bet with win probability `p`, net odds `b`.
///
/// `f* = (p (b + 1) - 1) / b`. For any real lottery this is negative, which is
/// the mathematically correct instruction: bet nothing.
double kellyFraction({required double p, required double netOdds}) =>
    (p * (netOdds + 1) - 1) / netOdds;
