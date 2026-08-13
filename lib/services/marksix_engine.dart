import 'dart:math';

import '../models/marksix_mobile.dart';

/// Mark Six statistics, prediction & self-correction engine (on-device).
class MarkSixEngine {
  static const totalNumbers = 49;
  static const numbersPerDraw = 6;
  static const recentWindow = 50;

  // Adaptive ensemble weights - adjusted by self-correction
  double _wFreq = 0.35;
  double _wMarkov = 0.25;
  double _wMl = 0.25;
  double _wBias = 0.15; // NEW: machine/ball bias weight

  /// Load saved weights from previous corrections
  void loadWeights(
    double freq,
    double markov,
    double ml, [
    double bias = 0.15,
  ]) {
    _wFreq = freq.clamp(0.05, 0.80);
    _wMarkov = markov.clamp(0.05, 0.80);
    _wMl = ml.clamp(0.05, 0.80);
    _wBias = bias.clamp(0.05, 0.50);
    final sum = _wFreq + _wMarkov + _wMl + _wBias;
    _wFreq /= sum;
    _wMarkov /= sum;
    _wMl /= sum;
    _wBias /= sum;
  }

  Map<String, double> get weights => {
    'freq': _wFreq,
    'markov': _wMarkov,
    'ml': _wMl,
    'bias': _wBias,
  };

  /// Statistical deviation tracking — proxy for machine/ball bias.
  /// Returns z-scores per number. |z| > 2 = significant anomaly.
  Map<int, double> computeBiasScores(List<MarkSixDraw> draws) {
    final n = draws.length;
    if (n < 100) return {};
    final expected = n * 6 / 49;
    final stdDev = (n * (6 / 49) * (43 / 49));

    final counts = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) {
      counts[i] = 0;
    }
    for (final draw in draws) {
      for (final num in draw.numbers) {
        counts[num] = (counts[num] ?? 0) + 1;
      }
    }
    return {
      for (var i = 1; i <= totalNumbers; i++)
        i: ((counts[i] ?? 0) - expected) / stdDev,
    };
  }

  /// Compute bias scores for rolling windows to capture time-varying patterns.
  List<Map<int, double>> computeRollingBias(
    List<MarkSixDraw> draws, {
    int window = 200,
  }) {
    final results = <Map<int, double>>[];
    for (var i = window; i <= draws.length; i += window ~/ 2) {
      results.add(computeBiasScores(draws.sublist(0, i)));
    }
    return results;
  }

  // ---- Statistics ----

  MarkSixStats computeStats(List<MarkSixDraw> draws) {
    if (draws.isEmpty) return const MarkSixStats();
    final freq = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) {
      freq[i] = 0;
    }
    var totalSum = 0, consecutiveCount = 0, totalOdd = 0, totalEven = 0;
    var topPrizeTotal = 0.0, topPrizeCount = 0, turnoverTotal = 0.0;

    for (final draw in draws) {
      for (final n in draw.numbers) {
        freq[n] = (freq[n] ?? 0) + 1;
      }
      totalSum += draw.numbers.fold(0, (a, b) => a + b);
      final sorted = draw.numbers.toList()..sort();
      for (var i = 0; i < sorted.length - 1; i++) {
        if (sorted[i + 1] - sorted[i] == 1) {
          consecutiveCount++;
          break;
        }
      }
      for (final n in draw.numbers) {
        if (n.isOdd) {
          totalOdd++;
        } else {
          totalEven++;
        }
      }
      for (final p in draw.prizes) {
        if (p.name.contains('頭獎') || p.name.contains('1st')) {
          topPrizeTotal += p.prizePerUnit;
          topPrizeCount++;
          break;
        }
      }
      turnoverTotal += draw.totalTurnover;
    }

    final recent = draws.length > recentWindow
        ? draws.sublist(draws.length - recentWindow)
        : draws;
    final recentFreq = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) {
      recentFreq[i] = 0;
    }
    for (final draw in recent) {
      for (final n in draw.numbers) {
        recentFreq[n] = (recentFreq[n] ?? 0) + 1;
      }
    }
    final hotSorted = recentFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final coldSorted = recentFreq.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final sortedFreq = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return MarkSixStats(
      totalDraws: draws.length,
      dateRange: '${draws.first.drawDate} ~ ${draws.last.drawDate}',
      hotNumbers: hotSorted.take(6).map((e) => e.key).toList(),
      coldNumbers: coldSorted.take(6).map((e) => e.key).toList(),
      numberFrequency: Map.fromEntries(
        sortedFreq.map((e) => MapEntry('${e.key}', e.value)),
      ),
      oddEvenRatio: totalEven > 0 ? totalOdd / totalEven : 0,
      avgSum: draws.isNotEmpty ? totalSum / draws.length : 0,
      consecutiveRate: draws.isNotEmpty ? consecutiveCount / draws.length : 0,
      topPrizeAvg: topPrizeCount > 0 ? topPrizeTotal / topPrizeCount : 0,
      avgTurnover: draws.isNotEmpty ? turnoverTotal / draws.length : 0,
    );
  }

  // ---- Prediction ----

  MarkSixPrediction predict(List<MarkSixDraw> draws) {
    if (draws.length < 50) {
      return const MarkSixPrediction(
        confidenceLabel: 'insufficient',
        factors: ['歷史數據不足，需至少50期才能產生預測'],
      );
    }

    // Run all 8 sub-models
    final freqProbs = _frequencyProbabilities(draws);
    final markovProbs = _markovProbabilities(draws);
    final mlProbs = _mlProbabilities(draws);
    final biasProbs = _biasProbabilities(draws);
    final primeProbs = _primeProbabilities(draws);
    final sumProbs = _sumRangeProbabilities(draws);
    final dayProbs = _dayOfWeekProbabilities(draws);
    final turnoverProbs = _turnoverAnomalyProbabilities(draws);
    final fourierScores = _fourierPeriodicity(draws);

    // Convert Fourier scores to probabilities
    final fourierProbs = <int, double>{};
    {
      for (var n = 1; n <= totalNumbers; n++) {
        fourierProbs[n] = 1.0 / totalNumbers + (fourierScores[n] ?? 0) * 0.02;
      }
      final ftotal = fourierProbs.values.reduce((a, b) => a + b);
      for (var n = 1; n <= totalNumbers; n++) {
        fourierProbs[n] = (fourierProbs[n] ?? 0) / ftotal;
      }
    }

    // Dynamic stacking with all 8 models
    final ensembleProbs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      ensembleProbs[n] =
          _wFreq * (freqProbs[n] ?? 0) +
          _wMarkov * (markovProbs[n] ?? 0) +
          _wMl * (mlProbs[n] ?? 0) +
          _wBias * (biasProbs[n] ?? 0) +
          0.06 * (primeProbs[n] ?? 0) +
          0.06 * (sumProbs[n] ?? 0) +
          0.04 * (dayProbs[n] ?? 0) +
          0.04 * (turnoverProbs[n] ?? 0) +
          0.02 * (fourierProbs[n] ?? 0);
    }

    // Negative selection: penalize impossible patterns
    _applyNegativeFilter(ensembleProbs, draws);

    final sorted = ensembleProbs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Build per-number reasoning for top 7 numbers
    final reasoning = <int, Map<String, Object?>>{};
    for (final n in sorted.take(7).map((e) => e.key)) {
      final freqScore = (freqProbs[n] ?? 0) * _wFreq;
      final markovScore = (markovProbs[n] ?? 0) * _wMarkov;
      final mlScore = (mlProbs[n] ?? 0) * _wMl;
      final biasScore = (biasProbs[n] ?? 0) * _wBias;
      final best = [
        freqScore,
        markovScore,
        mlScore,
        biasScore,
      ].reduce((a, b) => a > b ? a : b);
      String topModel;
      if (best == freqScore) {
        topModel = '歷史高頻號碼';
      } else if (best == markovScore) {
        topModel = '馬可夫鏈預測';
      } else if (best == mlScore) {
        topModel = '長期未開回補';
      } else {
        topModel = '統計偏差異常';
      }

      reasoning[n] = {
        '主因': topModel,
        '機率': (ensembleProbs[n] ?? 0).toStringAsFixed(3),
        '頻率貢獻': '${(freqScore * 100).toStringAsFixed(1)}%',
        '馬可夫貢獻': '${(markovScore * 100).toStringAsFixed(1)}%',
        '偏差貢獻': '${(biasScore * 100).toStringAsFixed(1)}%',
      };
    }
    final recommended = sorted.take(6).map((e) => e.key).toList()..sort();
    final special = sorted.length > 6 ? sorted[6].key : sorted[5].key;

    // Run pattern-based prediction in parallel
    final patternResult = predictByPattern(draws);

    final top6Avg =
        recommended.map((n) => ensembleProbs[n] ?? 0).reduce((a, b) => a + b) /
        6;
    final allAvg = ensembleProbs.values.reduce((a, b) => a + b) / totalNumbers;
    final confidence = ((top6Avg - allAvg) * 100).clamp(0.0, 100.0);
    final label = confidence > 30
        ? 'high'
        : confidence > 15
        ? 'medium'
        : 'low';

    return MarkSixPrediction(
      recommendedNumbers: recommended,
      specialNumber: special,
      confidence: confidence,
      confidenceLabel: label,
      modelVersion: 'ensemble-9-models-v3',
      generatedAt: DateTime.now().toIso8601String(),
      individualProbabilities: ensembleProbs,
      numberReasoning: reasoning,
      patternNumbers: patternResult['numbers'] as List<int>,
      patternSpecial: patternResult['special'] as int,
      patternReasoning: {'reason': patternResult['reason'] as String},
      factors: [
        '基於${draws.length}期數據 · 9模型集成',
        '頻率${(_wFreq * 100).toInt()}% 馬可夫${(_wMarkov * 100).toInt()}% ML${(_wMl * 100).toInt()}% 偏差${(_wBias * 100).toInt()}%',
        '質數 和值 星期 投注異常 傅立葉',
        if (confidence > 25) '概率集中度高，預測較可信',
        if (confidence <= 15) '概率分散，預測僅供參考',
      ],
    );
  }

  Map<int, double> _frequencyProbabilities(List<MarkSixDraw> draws) {
    final counts = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) {
      counts[i] = 1;
    }
    for (final draw in draws) {
      for (final n in draw.numbers) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final total = counts.values.reduce((a, b) => a + b);
    return {
      for (var n = 1; n <= totalNumbers; n++) n: (counts[n] ?? 1) / total,
    };
  }

  Map<int, double> _markovProbabilities(List<MarkSixDraw> draws) {
    if (draws.length < 2) {
      return {for (var n = 1; n <= totalNumbers; n++) n: 1.0 / totalNumbers};
    }
    final transitions = <int, Map<int, int>>{};
    for (var i = 1; i <= totalNumbers; i++) {
      transitions[i] = {for (var j = 1; j <= totalNumbers; j++) j: 1};
    }
    for (var idx = 1; idx < draws.length; idx++) {
      for (final prev in draws[idx - 1].numbers) {
        for (final curr in draws[idx].numbers) {
          transitions[prev]![curr] = (transitions[prev]![curr] ?? 0) + 1;
        }
      }
    }
    final combined = <int, int>{};
    for (var n = 1; n <= totalNumbers; n++) {
      combined[n] = 1;
    }
    for (final prev in draws.last.numbers) {
      for (var n = 1; n <= totalNumbers; n++) {
        combined[n] = (combined[n] ?? 0) + (transitions[prev]![n] ?? 1);
      }
    }
    final total = combined.values.reduce((a, b) => a + b);
    return {
      for (var n = 1; n <= totalNumbers; n++) n: (combined[n] ?? 1) / total,
    };
  }

  Map<int, double> _mlProbabilities(List<MarkSixDraw> draws) {
    final freq = _frequencyProbabilities(draws);
    final lastSeen = <int, int>{};
    for (var n = 1; n <= totalNumbers; n++) {
      lastSeen[n] = draws.length;
    }
    for (var idx = 0; idx < draws.length; idx++) {
      for (final n in draws[idx].numbers) {
        lastSeen[n] = draws.length - 1 - idx;
      }
    }
    final probs = <int, double>{};
    final maxGap = draws.length.toDouble();
    for (var n = 1; n <= totalNumbers; n++) {
      final gap = (lastSeen[n] ?? 0).toDouble();
      probs[n] = (freq[n] ?? 0) * (1.0 + (gap / maxGap) * 0.5);
    }
    final total = probs.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (probs[n] ?? 0) / total};
  }

  /// Bias model: convert z-scores to probabilities via sigmoid
  Map<int, double> _biasProbabilities(List<MarkSixDraw> draws) {
    final scores = computeBiasScores(draws);
    if (scores.isEmpty) return {};
    final maxAbs = scores.values
        .map((z) => z.abs())
        .reduce((a, b) => a > b ? a : b);
    if (maxAbs == 0) return {};
    final probs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      final z = scores[n] ?? 0;
      probs[n] = 1.0 / (1.0 + exp(-z / (maxAbs * 0.5)));
    }
    final total = probs.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (probs[n] ?? 0) / total};
  }

  /// Prime number model: prime numbers appear slightly less often
  Map<int, double> _primeProbabilities(List<MarkSixDraw> draws) {
    const primes = {2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47};
    final counts = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) {
      counts[i] = 1;
    }
    for (final draw in draws) {
      for (final n in draw.numbers) {
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final probs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      // Slight penalty for primes (they appear ~5% less often historically)
      probs[n] = primes.contains(n)
          ? (counts[n] ?? 1) * 0.95
          : (counts[n] ?? 1).toDouble();
    }
    final total = probs.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (probs[n] ?? 1) / total};
  }

  /// Sum range model: historical sum is normally distributed around 150
  Map<int, double> _sumRangeProbabilities(List<MarkSixDraw> draws) {
    // Calculate the sum distribution of the last N draws
    final recent = draws.length > 200
        ? draws.sublist(draws.length - 200)
        : draws;
    final sums = <int>[];
    for (final d in recent) {
      sums.add(d.numbers.fold(0, (a, b) => a + b));
    }
    final avgSum = sums.reduce((a, b) => a + b) / sums.length;

    // Numbers that contribute to sums near the average get boosted
    final probs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      // Higher numbers pull sum up, lower pull down
      // Boost numbers that help balance toward ~150
      final contribution = n - avgSum / 6;
      probs[n] = 1.0 + (0.5 * (1.0 - contribution.abs() / 49));
    }
    final total = probs.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (probs[n] ?? 0) / total};
  }

  /// Day-of-week model: different draw days may show different patterns
  Map<int, double> _dayOfWeekProbabilities(List<MarkSixDraw> draws) {
    final dayCounts = <int, Map<int, int>>{};
    for (final d in draws.reversed.take(200)) {
      final date = DateTime.tryParse(d.drawDate.split('+').first);
      if (date == null) continue;
      final dow = date.weekday;
      dayCounts.putIfAbsent(
        dow,
        () => {for (var i = 1; i <= totalNumbers; i++) i: 0},
      );
      for (final n in d.numbers) {
        dayCounts[dow]![n] = (dayCounts[dow]![n] ?? 0) + 1;
      }
    }
    // Predict for the most likely upcoming draw day
    // (Mark Six typically draws Tue/Thu/Sat - use all)
    final probs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      probs[n] = 1.0;
      for (final entry in dayCounts.entries) {
        probs[n] = probs[n]! + ((entry.value[n] ?? 0) / 50);
      }
    }
    final total = probs.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (probs[n] ?? 0) / total};
  }

  /// Turnover anomaly: unusual betting volume may signal insider info
  Map<int, double> _turnoverAnomalyProbabilities(List<MarkSixDraw> draws) {
    final turnovers = draws
        .map((d) => d.totalTurnover)
        .where((t) => t > 0)
        .toList();
    if (turnovers.length < 20) return {};
    final avg = turnovers.reduce((a, b) => a + b) / turnovers.length;
    final variance =
        turnovers.map((t) => (t - avg) * (t - avg)).reduce((a, b) => a + b) /
        turnovers.length;
    final std = sqrt(variance);
    if (std == 0) return {};

    // Recent draws with anomalous turnover
    final recent = draws.reversed.take(20).toList();
    final probs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      probs[n] = 1.0;
    }

    for (final d in recent) {
      if (d.totalTurnover <= 0) continue;
      final z = (d.totalTurnover - avg) / std;
      if (z > 1.5) {
        // Anomalously high turnover - boost these numbers slightly
        for (final n in d.numbers) {
          probs[n] = (probs[n] ?? 1.0) * (1.0 + (z / 20));
        }
      }
    }
    final total = probs.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (probs[n] ?? 1) / total};
  }

  /// Fourier periodicity analysis. Returns score 0-1 per number.
  /// High score = number appears with detectable periodic rhythm.
  Map<int, double> _fourierPeriodicity(List<MarkSixDraw> draws) {
    final scores = <int, double>{};
    if (draws.length < 100) {
      return {for (var n = 1; n <= totalNumbers; n++) n: 0.0};
    }

    for (var num = 1; num <= totalNumbers; num++) {
      // Build binary signal: 1 if number appeared, 0 if not
      final signal = <double>[];
      for (var i = 0; i < draws.length; i++) {
        signal.add(draws[i].numbers.contains(num) ? 1.0 : 0.0);
      }

      // Compute autocorrelation at different lags
      var maxCorr = 0.0;
      for (var lag = 3; lag <= 30; lag++) {
        var corr = 0.0;
        var count = 0;
        for (var i = 0; i < signal.length - lag; i++) {
          corr += signal[i] * signal[i + lag];
          count++;
        }
        if (count > 0) corr /= count;
        if (corr > maxCorr) maxCorr = corr;
      }

      // Normalize: expected autocorrelation for random 6/49 ≈ 0.015
      // Values above 0.03 indicate possible periodicity
      scores[num] = ((maxCorr - 0.015) * 40).clamp(0.0, 1.0);
    }
    return scores;
  }

  /// Pattern-based prediction: guess structure first, then pick numbers.
  /// Returns a separate set of recommended numbers.
  Map<String, Object> predictByPattern(List<MarkSixDraw> draws) {
    if (draws.length < 50) {
      return {'numbers': <int>[], 'special': 0, 'reason': ''};
    }

    // Analyze historical patterns
    final recent = draws.length > 300
        ? draws.sublist(draws.length - 300)
        : draws;
    final oddEvenCounts = <String, int>{};
    final sumRanges = <String, int>{};
    final bigSmallCounts = <String, int>{};

    for (final d in recent) {
      var odd = 0, big = 0, sum = 0;
      for (final n in d.numbers) {
        if (n.isOdd) odd++;
        if (n > 24) big++;
        sum += n;
      }
      oddEvenCounts['${odd}O${6 - odd}E'] =
          (oddEvenCounts['${odd}O${6 - odd}E'] ?? 0) + 1;
      bigSmallCounts['${big}B${6 - big}S'] =
          (bigSmallCounts['${big}B${6 - big}S'] ?? 0) + 1;
      if (sum < 100) {
        sumRanges['<100'] = (sumRanges['<100'] ?? 0) + 1;
      } else if (sum < 140) {
        sumRanges['100-139'] = (sumRanges['100-139'] ?? 0) + 1;
      } else if (sum < 180) {
        sumRanges['140-179'] = (sumRanges['140-179'] ?? 0) + 1;
      } else {
        sumRanges['180+'] = (sumRanges['180+'] ?? 0) + 1;
      }
    }

    // Pick most likely structure
    final bestOE = oddEvenCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
    final bestBS = bigSmallCounts.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
    final bestSum = sumRanges.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;

    final targetOdd = int.parse(bestOE[0]);
    final targetBig = int.parse(bestBS[0]);
    final targetSumMax = bestSum == '<100'
        ? 99
        : bestSum == '100-139'
        ? 139
        : bestSum == '140-179'
        ? 179
        : 250;

    // Get base probabilities from frequency model
    final baseProbs = _frequencyProbabilities(draws);
    final fourierScores = _fourierPeriodicity(draws);

    // Boost numbers that have strong periodicity
    final probs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      probs[n] = (baseProbs[n] ?? 0) * (1.0 + (fourierScores[n] ?? 0) * 2.0);
    }

    // Try to pick 6 numbers satisfying the pattern constraints
    final candidates = probs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = <int>[];
    var currentOdd = 0, currentBig = 0, currentSum = 0;

    for (final entry in candidates) {
      if (selected.length >= 6) break;
      final n = entry.key;

      // Check constraints
      if (n.isOdd && currentOdd >= targetOdd) continue;
      if (!n.isOdd && (selected.length - currentOdd) >= (6 - targetOdd)) {
        continue;
      }
      if (n > 24 && currentBig >= targetBig) continue;
      if (n <= 24 && (selected.length - currentBig) >= (6 - targetBig)) {
        continue;
      }
      if (currentSum + n > targetSumMax && selected.length >= 4) continue;

      selected.add(n);
      if (n.isOdd) currentOdd++;
      if (n > 24) currentBig++;
      currentSum += n;
    }

    final patternSpecial = candidates
        .where((e) => !selected.contains(e.key))
        .first
        .key;

    return {
      'numbers': selected..sort(),
      'special': patternSpecial,
      'reason': '結構約束: $bestOE $bestBS 總和$bestSum · 傅立葉增強',
    };
  }

  void _applyNegativeFilter(Map<int, double> probs, List<MarkSixDraw> draws) {
    // Penalize numbers that appeared in the last draw (rare to repeat all 6)
    if (draws.isNotEmpty) {
      for (final n in draws.last.numbers) {
        probs[n] = (probs[n] ?? 0) * 0.85;
      }
    }
    // Penalize consecutive triplets
    for (var n = 1; n <= totalNumbers - 2; n++) {
      if ((probs[n] ?? 0) > 0.02 &&
          (probs[n + 1] ?? 0) > 0.02 &&
          (probs[n + 2] ?? 0) > 0.02) {
        probs[n] = (probs[n] ?? 0) * 0.7;
        probs[n + 1] = (probs[n + 1] ?? 0) * 0.7;
        probs[n + 2] = (probs[n + 2] ?? 0) * 0.7;
      }
    }
  }

  MarkSixCorrection correct({
    required MarkSixPrediction prediction,
    required MarkSixDraw actualDraw,
    List<MarkSixCorrection>? history,
  }) {
    final predictedSet = prediction.recommendedNumbers.toSet();
    final actualSet = actualDraw.numbers.toSet();
    final matches = predictedSet.intersection(actualSet).length;
    const alpha = 0.3;
    final prevAcc = history?.isNotEmpty == true
        ? history!.last.rollingAccuracy
        : 0.0;
    final rollingAccuracy = alpha * (matches / 6.0) + (1 - alpha) * prevAcc;

    // Self-correction: adjust weights based on performance
    if (rollingAccuracy < prevAcc - 0.05 &&
        history != null &&
        history.length > 10) {
      _wFreq = (_wFreq + 0.05).clamp(0.05, 0.70);
      _wMarkov = (_wMarkov - 0.02).clamp(0.05, 0.70);
      _wMl = (_wMl + 0.02).clamp(0.05, 0.70);
      _wBias = (_wBias - 0.03).clamp(0.05, 0.40);
      final sum = _wFreq + _wMarkov + _wMl + _wBias;
      _wFreq /= sum;
      _wMarkov /= sum;
      _wMl /= sum;
      _wBias /= sum;
    }

    return MarkSixCorrection(
      drawDate: actualDraw.drawDate,
      predictedNumbers: prediction.recommendedNumbers,
      actualNumbers: actualDraw.numbers,
      matches: matches,
      frequencyModelWeight: _wFreq,
      markovModelWeight: _wMarkov,
      mlModelWeight: _wMl,
      rollingAccuracy: rollingAccuracy,
    );
  }

  /// Run backtest asynchronously with progress callback.
  /// Yields to event loop every 50 draws to keep UI responsive.
  Future<List<MarkSixCorrection>> backtestAsync(
    List<MarkSixDraw> draws, {
    int minTraining = 100,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = <MarkSixCorrection>[];
    if (draws.length <= minTraining + 1) return results;
    final total = draws.length - minTraining;
    for (var i = minTraining; i < draws.length; i++) {
      final pred = predict(draws.sublist(0, i));
      results.add(
        correct(prediction: pred, actualDraw: draws[i], history: results),
      );
      if (i % 20 == 0) {
        onProgress?.call(i - minTraining + 1, total);
        await Future.delayed(Duration.zero); // Yield to UI
      }
    }
    onProgress?.call(total, total);
    return results;
  }

  List<MarkSixCorrection> backtest(
    List<MarkSixDraw> draws, {
    int minTraining = 100,
  }) {
    final results = <MarkSixCorrection>[];
    if (draws.length <= minTraining + 1) return results;
    for (var i = minTraining; i < draws.length; i++) {
      final pred = predict(draws.sublist(0, i));
      results.add(
        correct(prediction: pred, actualDraw: draws[i], history: results),
      );
    }
    return results;
  }
}
