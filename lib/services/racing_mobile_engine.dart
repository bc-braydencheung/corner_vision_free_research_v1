import 'dart:math';

import '../models/racing_mobile.dart';
import 'race_context.dart';
import 'race_probability.dart';

class RacingMobileEngine {
  const RacingMobileEngine();

  static const featureCount = 17;

  /// Weight given to the de-vigged HKJC win pool when it is available.
  ///
  /// The pool aggregates money from people who can see the horses; it is the
  /// strongest free prior that exists for a Hong Kong race. It is a prior and
  /// not the answer, so the model keeps the majority of the weight.
  static const poolWeight = 0.45;

  /// Exponent of the favourite-longshot correction applied to the pool.
  static const favouriteLongshotExponent = 1.18;

  /// Henery discount used when expanding win probabilities into place
  /// probabilities.
  static const heneryExponent = 0.86;

  /// Share of the remaining weight handed to the pool when the free data cannot
  /// describe the conditions of the race.
  static const contextPoolWeight = 0.40;

  List<double> features({
    required MobileRacingDataset dataset,
    required Map<String, Object?> race,
    required Map<String, Object?> runner,
  }) {
    final horseId = runner['horseId'] as String;
    final jockey = runner['jockey'] as String? ?? '';
    final trainer = runner['trainer'] as String? ?? '';
    final horse = dataset.horses[horseId] ?? MobileEntityState();
    final jockeyState = dataset.jockeys[jockey] ?? MobileEntityState();
    final trainerState = dataset.trainers[trainer] ?? MobileEntityState();
    final fieldSize = (race['runners'] as List<Object?>).length;
    final distance = (race['distanceMetres'] as num? ?? 0).toInt();
    final band = (distance / 200).round();
    final distanceStarts = horse.distanceStarts[band] ?? 0;
    final distanceWins = horse.distanceWins[band] ?? 0;
    final when = DateTime.parse(race['date'] as String);
    final lastDate = horse.lastDate.isEmpty
        ? null
        : DateTime.tryParse(horse.lastDate);
    final lastDays = lastDate == null
        ? 90
        : max(when.difference(lastDate).inDays, 0);
    final parsedForm = RegExp(r'\d+')
        .allMatches(runner['lastSix'] as String? ?? '')
        .map((match) => int.parse(match.group(0)!))
        .map((position) => max(1 - (position - 1) / max(fieldSize - 1, 1), 0.0))
        .toList();
    final recentScore = parsedForm.isEmpty
        ? horse.recentScore
        : parsedForm.reduce((left, right) => left + right) / parsedForm.length;
    final raceClass =
        double.tryParse(race['raceClass'] as String? ?? '') ?? 2.5;
    return [
      ((runner['weight'] as num?)?.toDouble() ?? 126) / 10 - 12.6,
      (((runner['draw'] as num?)?.toDouble() ?? (fieldSize + 1) / 2) - 1) /
          max(fieldSize - 1, 1),
      distance / 1000,
      race['venueCode'] == 'HV' ? 1 : 0,
      race['surface'] == 'AWT' ? 1 : 0,
      raceClass,
      log(horse.starts + 1),
      _rate(horse.wins, horse.starts, 0.08, 12),
      _rate(horse.places, horse.starts, 0.25, 12),
      horse.finishScore,
      _rate(distanceWins, distanceStarts, 0.08, 8),
      log(lastDays + 1) / log(181),
      _rate(jockeyState.wins, jockeyState.starts, 0.08, 30),
      _rate(jockeyState.places, jockeyState.starts, 0.25, 30),
      _rate(trainerState.wins, trainerState.starts, 0.08, 30),
      _rate(trainerState.places, trainerState.starts, 0.25, 30),
      recentScore,
    ];
  }

  /// [poolOdds] maps a race id to the latest public win odds of that race,
  /// keyed by horse code or by zero padded saddle cloth number.
  List<Map<String, Object?>> predictRaces({
    required List<Map<String, Object?>> races,
    required MobileRacingDataset dataset,
    MobileRacingModel? model,
    Map<String, Map<String, double>> poolOdds = const {},
    Map<String, RacingWeatherSnapshot> weather = const {},
  }) {
    return races.map((race) {
      final runners = (race['runners'] as List<Object?>)
          .map((runner) => (runner as Map).cast<String, Object?>())
          .toList();
      final featureRows = runners
          .map(
            (runner) => features(dataset: dataset, race: race, runner: runner),
          )
          .toList();
      final distance = (race['distanceMetres'] as num? ?? 0).toInt();
      final sprintBiases = runners
          .map(
            (runner) => sprintBias(
              dataset.horses[runner['horseId']] ?? MobileEntityState(),
              distance,
            ),
          )
          .toList();
      final context = RaceContext(
        venueCode: race['venueCode'] as String? ?? '',
        distanceMetres: distance,
        fieldSize: runners.length,
        going: race['going'] as String? ?? '',
        pace: classifyPace(sprintBiases),
        weather: weather[race['raceId'] as String?],
      );
      final useFitted = model?.useWinModel ?? false;
      final utilities = <double>[];
      for (var index = 0; index < runners.length; index++) {
        final runner = runners[index];
        final row = featureRows[index];
        // The draw is already a fitted feature, so the geometric prior only
        // stands in while the baseline is ranking the field.
        final drawPrior = useFitted
            ? 0.0
            : drawBias(
                venueCode: context.venueCode,
                distanceMetres: distance,
                draw: (runner['draw'] as num?)?.toInt(),
                fieldSize: runners.length,
              );
        utilities.add(
          (useFitted
                  ? _dot(model!.winWeights, row) + model.winIntercept
                  : _baselineScore(row)) +
              drawPrior +
              paceAdjustment(context.pace, sprintBiases[index]),
        );
        final names = dataset.horseNames[runner['horseId']];
        if (names != null) {
          runner['horseNameEnglish'] = names.first;
          runner['horseNameChinese'] = names.length > 1 ? names[1] : '';
        }
      }
      final modelWin = conditionalLogit(utilities);
      final market = correctFavouriteLongshot(
        poolProbabilities(_poolOddsFor(race, runners, poolOdds)),
        exponent: favouriteLongshotExponent,
      );
      // The less the free data can say about the conditions, the more of the
      // answer is handed to the money.
      final effectivePoolWeight = market.isEmpty
          ? 0.0
          : poolWeight +
                (1 - poolWeight) * contextPoolWeight * context.uncertainty;
      final win = blendDistributions(modelWin, market, effectivePoolWeight);
      final placeSlots = placeSlotsForField(runners.length);
      final place = harvillePlaceProbabilities(
        win,
        placeSlots,
        henery: heneryExponent,
      );
      final separation = 1 - normalisedEntropy(win);
      final predicted = <Map<String, Object?>>[];
      for (var index = 0; index < runners.length; index++) {
        final winProbability = win[index];
        final placeProbability = place[index];
        final confidenceScore = _confidence(
          winProbability: winProbability,
          fieldSize: runners.length,
          separation: separation,
          audited: useFitted,
          hasMarket: market.isNotEmpty,
          uncertainty: context.uncertainty,
        );
        predicted.add({
          ...runners[index],
          'winProbability': winProbability,
          'placeProbability': placeProbability,
          'modelWinProbability': modelWin[index],
          if (market.isNotEmpty) 'marketWinProbability': market[index],
          'poolWeight': effectivePoolWeight,
          'paceScenario': context.pace.label,
          'contextUncertainty': context.uncertainty,
          'contextLabel': context.label,
          'fairWinOdds': 1 / max(winProbability, 0.001),
          'fairPlaceOdds': placeProbability == 0
              ? 0.0
              : 1 / max(placeProbability, 0.001),
          'confidence': confidenceScore >= 0.72
              ? 'high'
              : confidenceScore >= 0.55
              ? 'medium'
              : 'low',
          'confidenceScore': confidenceScore,
          'recommendation': confidenceScore < 0.48
              ? 'no-prediction'
              : 'model-view',
          'factors': <String>[
            model == null ? '手機動態往績基準' : '手機可恢復排名模型',
            '條件 logit 賽事層機率',
            if (placeSlots > 0) 'Henery–Harville 位置展開',
            if (market.isNotEmpty) '馬會獨贏池先驗（已修正熱門–冷門偵斜）',
            context.pace.label,
            if (context.wet) '濕地／不確定度較高，已加重市場權重',
            if (context.weather != null) '天文台免費實時觀測',
          ],
        });
      }
      return {...race, 'runners': predicted};
    }).toList();
  }

  int appendResults(
    MobileRacingDataset dataset,
    List<Map<String, Object?>> races,
  ) {
    var added = 0;
    final existingRaceIds = dataset.rows.map((row) => row.raceId).toSet();
    for (final race in races) {
      if (!existingRaceIds.add(race['raceId'] as String)) {
        continue;
      }
      final runners = (race['runners'] as List<Object?>)
          .map((value) => (value as Map).cast<String, Object?>())
          .toList();
      final date = race['date'] as String;
      final fieldSize = runners.length;
      final pending =
          <({Map<String, Object?> runner, List<double> features})>[];
      for (final runner in runners) {
        final featureRow = features(
          dataset: dataset,
          race: race,
          runner: runner,
        );
        final finish = (runner['finishPosition'] as num).toInt();
        final placeSlots = fieldSize >= 7
            ? 3
            : fieldSize >= 4
            ? 2
            : 0;
        final row = RacingTrainingRow(
          raceId: race['raceId'] as String,
          date: date,
          fieldSize: fieldSize,
          won: finish == 1 ? 1 : 0,
          placed: finish <= placeSlots ? 1 : 0,
          features: featureRow,
        );
        dataset.rows.add(row);
        pending.add((runner: runner, features: featureRow));
        dataset.results.add({
          'raceId': row.raceId,
          'horseId': runner['horseId'] as String,
          'finishPosition': finish,
        });
        final english = runner['horseNameEnglish'] as String? ?? '';
        final chinese = runner['horseNameChinese'] as String? ?? '';
        if (english.isNotEmpty || chinese.isNotEmpty) {
          dataset.horseNames[runner['horseId'] as String] = [english, chinese];
        }
        added++;
      }
      for (final item in pending) {
        final runner = item.runner;
        final finish = (runner['finishPosition'] as num).toInt();
        final score = max(1 - (finish - 1) / max(fieldSize - 1, 1), 0.0);
        final won = finish == 1 ? 1 : 0;
        final placeSlots = fieldSize >= 7
            ? 3
            : fieldSize >= 4
            ? 2
            : 0;
        final placed = finish <= placeSlots ? 1 : 0;
        final horseId = runner['horseId'] as String;
        final jockey = runner['jockey'] as String? ?? '';
        final trainer = runner['trainer'] as String? ?? '';
        final horse = dataset.horses.putIfAbsent(
          horseId,
          MobileEntityState.new,
        );
        horse.update(won: won, placed: placed, score: score, date: date);
        final band = ((race['distanceMetres'] as num).toInt() / 200).round();
        horse.distanceStarts[band] = (horse.distanceStarts[band] ?? 0) + 1;
        horse.distanceWins[band] = (horse.distanceWins[band] ?? 0) + won;
        dataset.jockeys
            .putIfAbsent(jockey, MobileEntityState.new)
            .update(won: won, placed: placed, score: score, date: date);
        dataset.trainers
            .putIfAbsent(trainer, MobileEntityState.new)
            .update(won: won, placed: placed, score: score, date: date);
      }
      if (pending.isNotEmpty && date.compareTo(dataset.trainedThrough) > 0) {
        dataset.trainedThrough = date;
      }
    }
    if (added > 0) {
      dataset.datasetVersion = _nextVersion(
        dataset.datasetVersion,
        dataset.trainedThrough,
        dataset.rows.length,
      );
      if (dataset.results.length > 700) {
        dataset.results.removeRange(0, dataset.results.length - 700);
      }
    }
    return added;
  }

  static List<double> normalise(List<double> values, double target) {
    if (target == 0 || values.isEmpty) {
      return List<double>.filled(values.length, 0);
    }
    final clipped = values.map((value) => max(value, 0.000001)).toList();
    final total = clipped.reduce((left, right) => left + right);
    final probabilities = clipped
        .map((value) => value / total * target)
        .toList();
    for (var iteration = 0; iteration < 5; iteration++) {
      var excess = 0.0;
      final under = <int>[];
      for (var index = 0; index < probabilities.length; index++) {
        if (probabilities[index] > 0.98) {
          excess += probabilities[index] - 0.98;
          probabilities[index] = 0.98;
        } else {
          under.add(index);
        }
      }
      if (excess == 0 || under.isEmpty) {
        break;
      }
      final underTotal = under.fold<double>(
        0,
        (sum, index) => sum + probabilities[index],
      );
      for (final index in under) {
        probabilities[index] += excess * probabilities[index] / underTotal;
      }
    }
    return probabilities;
  }

  /// Reads the stored pool quotes for [race] in runner order.
  static List<double?> _poolOddsFor(
    Map<String, Object?> race,
    List<Map<String, Object?>> runners,
    Map<String, Map<String, double>> poolOdds,
  ) {
    final quotes = poolOdds[race['raceId'] as String?];
    if (quotes == null || quotes.isEmpty) {
      return List<double?>.filled(runners.length, null);
    }
    return runners.map((runner) {
      final horseId = runner['horseId'] as String? ?? '';
      final number = (runner['number'] as num?)?.toInt();
      return quotes[horseId] ??
          (number == null
              ? null
              : quotes[number.toString().padLeft(2, '0')] ??
                    quotes[number.toString()]);
    }).toList();
  }

  /// Confidence is a research score, never a claim about the win frequency.
  ///
  /// It rises with how far a runner sits from a blind field-size guess and with
  /// how much structure the race has, and it is capped until the recoverable
  /// ranking model has actually been fitted.
  static double _confidence({
    required double winProbability,
    required int fieldSize,
    required double separation,
    required bool audited,
    required bool hasMarket,
    required double uncertainty,
  }) {
    final uniform = 1 / max(fieldSize, 1);
    final deviation = ((winProbability - uniform) / uniform).abs();
    final raw =
        (0.34 +
            0.30 * min(deviation, 1.5) / 1.5 +
            0.22 * separation +
            (hasMarket ? 0.09 : 0.0)) *
        (1 - 0.30 * uncertainty);
    return audited ? min(raw, 0.95) : min(raw, 0.54);
  }

  static double _baselineScore(List<double> row) =>
      1.6 * row[7] +
      0.8 * row[9] +
      0.55 * row[12] +
      0.55 * row[14] +
      0.35 * row[16] -
      0.12 * row[0];

  static double _rate(int successes, int starts, double prior, int strength) =>
      (successes + prior * strength) / (starts + strength);

  static double _dot(List<double> weights, List<double> features) {
    var value = 0.0;
    for (var index = 0; index < weights.length; index++) {
      value += weights[index] * features[index];
    }
    return value;
  }

  static String _nextVersion(String previous, String date, int rows) {
    var hash = 2166136261;
    for (final unit in '$previous:$date:$rows'.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return '$date-${hash.toRadixString(16).padLeft(8, '0')}';
  }
}
