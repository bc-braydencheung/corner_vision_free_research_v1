import 'dart:math' as math;

import '../core/combinatorics.dart';
import 'distributions.dart';

class PowerResult {
  const PowerResult({
    required this.baselineRate,
    required this.alternativeRate,
    required this.requiredDraws,
    required this.requiredYears,
    required this.achievedPower,
    required this.detectableEffectAtAvailable,
    required this.availableDraws,
  });

  final double baselineRate;
  final double alternativeRate;

  /// Draws needed to reach the requested power.
  final double requiredDraws;

  final double requiredYears;

  /// Power actually achieved with [availableDraws].
  final double achievedPower;

  /// Smallest relative bias detectable with 80% power given [availableDraws].
  final double detectableEffectAtAvailable;

  final int availableDraws;
}

/// The calculation that ends the argument.
///
/// A single ball appears with probability `p0 = 6/49` per draw. To detect a
/// relative bias `e` at significance `alpha` (Bonferroni-corrected across 49
/// balls) and power `1 - beta`:
///
///   `n = (z_{alpha/2} + z_beta)^2 p0 (1 - p0) / (p0 e)^2`
///
/// For a 5% bias, that is tens of thousands of draws - centuries of Mark Six.
/// Physics allows a bias of order 0.1%; statistics says nobody will ever know
/// which ball it favours. The intersection of the two is an impossibility proof,
/// not a difficulty.
class PowerAnalysis {
  static PowerResult forRelativeBias({
    required double relativeBias,
    int availableDraws = 3000,
    double drawsPerYear = 152,
    double alpha = 0.05,
    double power = 0.80,
    bool bonferroni = true,
  }) {
    final p0 = kPickCount / kBallCount;
    final effectiveAlpha = bonferroni ? alpha / kBallCount : alpha;
    final zAlpha = normalQuantile(1 - effectiveAlpha / 2);
    final zBeta = normalQuantile(power);
    final delta = p0 * relativeBias;
    final p1 = p0 * (1 + relativeBias);

    final required =
        math.pow(zAlpha + zBeta, 2) * p0 * (1 - p0) / (delta * delta);

    final achieved = availableDraws <= 0
        ? 0.0
        : normalCdf(
            delta.abs() / math.sqrt(p0 * (1 - p0) / availableDraws) - zAlpha,
          );

    final detectable = availableDraws <= 0
        ? double.infinity
        : (zAlpha + zBeta) * math.sqrt(p0 * (1 - p0) / availableDraws) / p0;

    return PowerResult(
      baselineRate: p0,
      alternativeRate: p1,
      requiredDraws: required,
      requiredYears: required / drawsPerYear,
      achievedPower: achieved.clamp(0.0, 1.0),
      detectableEffectAtAvailable: detectable,
      availableDraws: availableDraws,
    );
  }
}

/// Maximum-entropy link between a ball's mass defect and its release
/// probability: `dP/P = -kappa * dm/m`.
///
/// Under the constraints of fixed mean mass and fixed mass variance, the
/// first-order response of the release probability to a mass perturbation is
/// linear, with a machine-dependent sensitivity `kappa` (larger for air-blower
/// machines, where a lighter ball is lifted more easily, than for gravity
/// drums). This converts an engineering tolerance into a probability bias.
double biasFromMassDefect({
  required double relativeMassDefect,
  double kappa = 3.0,
}) => -kappa * relativeMassDefect;
