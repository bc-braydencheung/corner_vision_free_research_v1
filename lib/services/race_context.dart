/// Track, pace and weather context of a Hong Kong race.
///
/// Everything here is either published for free or derived from the local
/// result history. The adjustments are deliberately small and are labelled as
/// heuristics: they are structural priors about how a race unfolds, not fitted
/// coefficients, so they must never overwhelm the fitted ranking model or the
/// public pool.
library;

import 'dart:math';

import '../models/racing_mobile.dart';

/// How much early speed is entered, and therefore how the race is likely to be
/// run.
enum PaceScenario {
  /// Several confirmed front runners: the early pace burns out, closers gain.
  fast,

  /// A normal spread of running styles.
  even,

  /// Almost no early speed: the leader is unpressured and hard to catch.
  slow,
}

extension PaceScenarioLabel on PaceScenario {
  String get label => switch (this) {
    PaceScenario.fast => '快步速（前領受壓）',
    PaceScenario.even => '均勻步速',
    PaceScenario.slow => '慢步速（前領有利）',
  };
}

/// A runner's tendency to be quick early, inferred from where its wins sit
/// relative to today's distance.
///
/// A horse whose record is built at shorter trips is the closest free proxy for
/// early speed that the public result pages support; sectional times are only
/// published per race and are not part of the free result history.
double sprintBias(MobileEntityState horse, int distanceMetres) {
  final todayBand = (distanceMetres / 200).round();
  var shorter = 0;
  var longer = 0;
  horse.distanceStarts.forEach((band, starts) {
    if (band < todayBand) {
      shorter += starts;
    } else if (band > todayBand) {
      longer += starts;
    }
  });
  final total = shorter + longer;
  if (total < 3) {
    return 0;
  }
  return (shorter - longer) / total;
}

/// Share of the field that looks like early speed, mapped to a scenario.
PaceScenario classifyPace(List<double> sprintBiases) {
  if (sprintBiases.length < 4) {
    return PaceScenario.even;
  }
  final leaders = sprintBiases.where((bias) => bias > 0.34).length;
  final share = leaders / sprintBiases.length;
  if (share >= 0.30) {
    return PaceScenario.fast;
  }
  if (share <= 0.08) {
    return PaceScenario.slow;
  }
  return PaceScenario.even;
}

/// Log-utility adjustment of one runner for the pace scenario.
///
/// Capped at ±0.09, i.e. under a 10% relative move of a runner's win
/// probability, because the scenario is inferred rather than measured.
double paceAdjustment(PaceScenario scenario, double sprintBias) {
  final bounded = sprintBias.clamp(-1.0, 1.0);
  return switch (scenario) {
    PaceScenario.fast => -0.09 * bounded,
    PaceScenario.slow => 0.09 * bounded,
    PaceScenario.even => 0.0,
  };
}

/// Log-utility adjustment for the barrier draw.
///
/// Hong Kong publishes the draw for free and the inside-draw advantage of the
/// tight Happy Valley circuit and of the short Sha Tin trips is a track
/// geometry effect, so it is a legitimate structural prior. It is still a
/// heuristic and stays inside ±0.12.
double drawBias({
  required String venueCode,
  required int distanceMetres,
  required int? draw,
  required int fieldSize,
}) {
  if (draw == null || draw <= 0 || fieldSize < 4) {
    return 0;
  }
  // -0.5 for the inside stall, +0.5 for the outside stall.
  final position = (draw - 1) / max(fieldSize - 1, 1) - 0.5;
  final venue = venueCode.toUpperCase();
  final strength = venue == 'HV'
      ? (distanceMetres <= 1800 ? 0.24 : 0.16)
      : (distanceMetres <= 1200
            ? 0.20
            : distanceMetres <= 1650
            ? 0.12
            : 0.06);
  return (-strength * position).clamp(-0.12, 0.12);
}

/// Free context of one race.
class RaceContext {
  const RaceContext({
    required this.venueCode,
    required this.distanceMetres,
    required this.fieldSize,
    this.going = '',
    this.pace = PaceScenario.even,
    this.weather,
  });

  final String venueCode;
  final int distanceMetres;
  final int fieldSize;
  final String going;
  final PaceScenario pace;
  final RacingWeatherSnapshot? weather;

  /// `true` when the going or the observed rainfall says the surface is wet.
  bool get wet {
    final normalised = going.toUpperCase();
    if (normalised.contains('WET') ||
        normalised.contains('SOFT') ||
        normalised.contains('YIELDING') ||
        normalised.contains('SLOW')) {
      return true;
    }
    return (weather?.rainfallMm ?? 0) >= 1.0;
  }

  /// How much of the race the free data cannot describe, from `0` to `1`.
  ///
  /// A wet surface, a large field and a missing going report all make the
  /// finishing order less a function of the runner ratings. It is used to lean
  /// harder on the public pool and to lower the confidence, never to change a
  /// runner's ranking.
  double get uncertainty {
    var score = 0.0;
    if (wet) {
      score += 0.45;
    }
    if (going.isEmpty) {
      score += 0.15;
    }
    if (weather == null) {
      score += 0.10;
    }
    if (fieldSize >= 12) {
      score += 0.20;
    } else if (fieldSize >= 10) {
      score += 0.10;
    }
    final humidity = weather?.humidity;
    if (humidity != null && humidity >= 0.90) {
      score += 0.10;
    }
    return score.clamp(0.0, 1.0);
  }

  /// Short研究 label for the UI and the audit trail.
  String get label {
    final parts = <String>[
      pace.label,
      if (going.isNotEmpty) '場地：$going',
      if (wet) '濕地',
      if (weather != null)
        '${weather!.district} ${weather!.temperatureC.toStringAsFixed(1)}°C'
            '${weather!.rainfallMm > 0 ? ' · 雨量 ${weather!.rainfallMm.toStringAsFixed(1)}mm' : ''}',
    ];
    return parts.join(' · ');
  }
}
