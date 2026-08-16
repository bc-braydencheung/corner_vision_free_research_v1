import 'dart:math' as math;

import '../core/combinatorics.dart';

const double kBoltzmann = 1.380649e-23;
const double kHBar = 1.054571817e-34;
const double kPlanckLength = 1.616255e-35;

/// Physical upper bound on how much information about the outcome of a Mark Six
/// draw can survive the mixing process.
///
/// The draw is a chaotic hard-sphere system. Trajectory separations grow as
/// `exp(lambda t)` with `lambda ~ nu * ln A`, where `nu` is the per-ball
/// collision rate and `A` the per-collision amplification of an angular error.
/// The mutual information between initial state and outcome therefore decays as
/// `I(t) = I0 * exp(-lambda t)`, with `I0 = log2 C(49,6) = 23.74` bits.
///
/// Two irreducible noise floors set the initial uncertainty:
///   thermal:  dx_th = sqrt(kB T / m) / nu   (equipartition velocity noise
///             integrated over one collision interval)
///   quantum:  dx_q  = sqrt(hbar / (2 m nu)) (standard quantum limit over the
///             same interval)
///
/// All numbers are order-of-magnitude estimates for a plausible machine; the
/// model exposes every parameter so the conclusion can be stress-tested rather
/// than believed.
class PredictabilityParams {
  const PredictabilityParams({
    this.collisionRate = 50.0,
    this.amplificationPerCollision = math.e,
    this.chamberScale = 0.30,
    this.ballMass = 2.7e-3,
    this.airTemperature = 297.0,
    this.stirTime = 45.0,
    this.controlUncertainty = 1e-4,
  });

  /// Collisions per second experienced by one ball (`nu`).
  final double collisionRate;

  /// Error amplification per collision (`A`), of order `d / mean free path`.
  final double amplificationPerCollision;

  /// Chamber length scale in metres (`L`).
  final double chamberScale;

  /// Ball mass in kg (`m`).
  final double ballMass;

  /// Air temperature in kelvin (`T`).
  final double airTemperature;

  /// Duration of mixing before the first ball is released, in seconds (`T`).
  final double stirTime;

  /// Best achievable engineering control of the initial ball positions (`dx0`).
  final double controlUncertainty;

  PredictabilityParams copyWith({
    double? collisionRate,
    double? amplificationPerCollision,
    double? chamberScale,
    double? ballMass,
    double? airTemperature,
    double? stirTime,
    double? controlUncertainty,
  }) => PredictabilityParams(
    collisionRate: collisionRate ?? this.collisionRate,
    amplificationPerCollision:
        amplificationPerCollision ?? this.amplificationPerCollision,
    chamberScale: chamberScale ?? this.chamberScale,
    ballMass: ballMass ?? this.ballMass,
    airTemperature: airTemperature ?? this.airTemperature,
    stirTime: stirTime ?? this.stirTime,
    controlUncertainty: controlUncertainty ?? this.controlUncertainty,
  );
}

class PredictabilityReport {
  const PredictabilityReport({
    required this.lyapunovExponent,
    required this.lyapunovTime,
    required this.bitsDestroyedPerSecond,
    required this.thermalFloor,
    required this.quantumFloor,
    required this.macroTimeFromControl,
    required this.macroTimeFromThermal,
    required this.macroTimeFromQuantum,
    required this.log10InformationBits,
    required this.requiredPrecisionMetres,
    required this.log10RequiredPrecisionMetres,
    required this.log10PrecisionOverPlanck,
    required this.initialInformationBits,
  });

  /// `lambda`, in inverse seconds.
  final double lyapunovExponent;

  /// `1 / lambda`, in seconds.
  final double lyapunovTime;

  /// `lambda / ln 2`: bits of initial-condition knowledge erased per second.
  final double bitsDestroyedPerSecond;

  final double thermalFloor;
  final double quantumFloor;

  /// Time for each uncertainty to be amplified to the chamber scale.
  final double macroTimeFromControl;
  final double macroTimeFromThermal;
  final double macroTimeFromQuantum;

  /// `log10` of the surviving mutual information in bits (hugely negative).
  final double log10InformationBits;

  /// Initial-position precision that would be needed to retain one bit. This
  /// underflows to zero for realistic mixing times, so display code should use
  /// [log10RequiredPrecisionMetres].
  final double requiredPrecisionMetres;

  final double log10RequiredPrecisionMetres;

  /// `log10(requiredPrecision / Planck length)`; negative means the required
  /// precision is finer than the Planck length, i.e. physically meaningless.
  final double log10PrecisionOverPlanck;

  final double initialInformationBits;

  bool get belowPlanckScale => log10PrecisionOverPlanck < 0;
}

PredictabilityReport computePredictability(PredictabilityParams p) {
  final lambda = p.collisionRate * math.log(p.amplificationPerCollision);
  final tau = 1.0 / p.collisionRate;

  final thermalFloor =
      math.sqrt(kBoltzmann * p.airTemperature / p.ballMass) * tau;
  final quantumFloor = math.sqrt(kHBar * tau / (2 * p.ballMass));

  double macroTime(double dx) => math.log(p.chamberScale / dx) / lambda;

  final i0 = kDrawEntropyBits;
  final log10Bits = (math.log(i0) - lambda * p.stirTime) / math.ln10;

  final log10Required =
      (math.log(p.chamberScale) - lambda * p.stirTime) / math.ln10;

  return PredictabilityReport(
    lyapunovExponent: lambda,
    lyapunovTime: 1.0 / lambda,
    bitsDestroyedPerSecond: lambda / math.ln2,
    thermalFloor: thermalFloor,
    quantumFloor: quantumFloor,
    macroTimeFromControl: macroTime(p.controlUncertainty),
    macroTimeFromThermal: macroTime(thermalFloor),
    macroTimeFromQuantum: macroTime(quantumFloor),
    log10InformationBits: log10Bits,
    requiredPrecisionMetres: math.pow(10, log10Required).toDouble(),
    log10RequiredPrecisionMetres: log10Required,
    log10PrecisionOverPlanck:
        log10Required - (math.log(kPlanckLength) / math.ln10),
    initialInformationBits: i0,
  );
}
