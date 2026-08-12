import 'dart:isolate';
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
  void loadWeights(double freq, double markov, double ml, [double bias = 0.15]) {
    _wFreq = freq.clamp(0.05, 0.80);
    _wMarkov = markov.clamp(0.05, 0.80);
    _wMl = ml.clamp(0.05, 0.80);
    _wBias = bias.clamp(0.05, 0.50);
    final sum = _wFreq + _wMarkov + _wMl + _wBias;
    _wFreq /= sum; _wMarkov /= sum; _wMl /= sum; _wBias /= sum;
  }

  Map<String, double> get weights => {
    'freq': _wFreq, 'markov': _wMarkov, 'ml': _wMl, 'bias': _wBias,
  };

  /// Statistical deviation tracking — proxy for machine/ball bias.
  /// Returns z-scores per number. |z| > 2 = significant anomaly.
  Map<int, double> computeBiasScores(List<MarkSixDraw> draws) {
    final n = draws.length;
    if (n < 100) return {};
    final expected = n * 6 / 49;
    final stdDev = (n * (6 / 49) * (43 / 49));

    final counts = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) counts[i] = 0;
    for (final draw in draws) {
      for (final num in draw.numbers) counts[num] = (counts[num] ?? 0) + 1;
    }
    return {
      for (var i = 1; i <= totalNumbers; i++)
        i: ((counts[i] ?? 0) - expected) / stdDev
    };
  }

  /// Compute bias scores for rolling windows to capture time-varying patterns.
  List<Map<int, double>> computeRollingBias(List<MarkSixDraw> draws, {int window = 200}) {
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
    for (var i = 1; i <= totalNumbers; i++) { freq[i] = 0; }
    var totalSum = 0, consecutiveCount = 0, totalOdd = 0, totalEven = 0;
    var topPrizeTotal = 0.0, topPrizeCount = 0, turnoverTotal = 0.0;

    for (final draw in draws) {
      for (final n in draw.numbers) { freq[n] = (freq[n] ?? 0) + 1; }
      totalSum += draw.numbers.fold(0, (a, b) => a + b);
      final sorted = draw.numbers.toList()..sort();
      for (var i = 0; i < sorted.length - 1; i++) {
        if (sorted[i + 1] - sorted[i] == 1) { consecutiveCount++; break; }
      }
      for (final n in draw.numbers) { if (n.isOdd) totalOdd++; else totalEven++; }
      for (final p in draw.prizes) {
        if (p.name.contains('頭獎') || p.name.contains('1st')) {
          topPrizeTotal += p.prizePerUnit; topPrizeCount++; break;
        }
      }
      turnoverTotal += draw.totalTurnover;
    }

    final recent = draws.length > recentWindow
        ? draws.sublist(draws.length - recentWindow) : draws;
    final recentFreq = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) { recentFreq[i] = 0; }
    for (final draw in recent) {
      for (final n in draw.numbers) { recentFreq[n] = (recentFreq[n] ?? 0) + 1; }
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
        sortedFreq.map((e) => MapEntry('${e.key}', e.value))),
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
    final freqProbs = _frequencyProbabilities(draws);
    final markovProbs = _markovProbabilities(draws);
    final mlProbs = _mlProbabilities(draws);
    final biasScores = computeBiasScores(draws);

    // Convert z-scores to probabilities
    final biasProbs = <int, double>{};
    if (biasScores.isNotEmpty) {
      final maxAbs = biasScores.values.map((z) => z.abs()).reduce((a, b) => a > b ? a : b);
      for (var n = 1; n <= totalNumbers; n++) {
        // Sigmoid: higher z-score → higher probability
        final z = biasScores[n] ?? 0;
        biasProbs[n] = 1.0 / (1.0 + (-z / (maxAbs * 0.5)).exp());
      }
      // Normalize
      final total = biasProbs.values.reduce((a, b) => a + b);
      for (var n = 1; n <= totalNumbers; n++) {
        biasProbs[n] = (biasProbs[n] ?? 0) / total;
      }
    }

    final ensembleProbs = <int, double>{};
    for (var n = 1; n <= totalNumbers; n++) {
      ensembleProbs[n] = _wFreq * (freqProbs[n] ?? 0) +
          _wMarkov * (markovProbs[n] ?? 0) +
          _wMl * (mlProbs[n] ?? 0) +
          _wBias * (biasProbs[n] ?? 0);
    }

    final sorted = ensembleProbs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final recommended = sorted.take(6).map((e) => e.key).toList()..sort();
    final special = sorted.length > 6 ? sorted[6].key : sorted[5].key;

    final top6Avg = recommended
        .map((n) => ensembleProbs[n] ?? 0)
        .reduce((a, b) => a + b) / 6;
    final allAvg = ensembleProbs.values.reduce((a, b) => a + b) / totalNumbers;
    final confidence = ((top6Avg - allAvg) * 100).clamp(0.0, 100.0);
    final label = confidence > 30 ? 'high' : confidence > 15 ? 'medium' : 'low';

    return MarkSixPrediction(
      recommendedNumbers: recommended, specialNumber: special,
      confidence: confidence, confidenceLabel: label,
      modelVersion: 'mobile-ensemble-1.0',
      generatedAt: DateTime.now().toIso8601String(),
      individualProbabilities: ensembleProbs,
      factors: [
        '基於${draws.length}期歷史數據',
        '集成: 頻率(${(_wFreq*100).toInt()}%) 馬可夫(${(_wMarkov*100).toInt()}%) ML(${(_wMl*100).toInt()}%) 偏差(${(_wBias*100).toInt()}%)',
        if (confidence > 25) '概率集中度高，預測較可信',
        if (confidence <= 15) '概率分散，預測僅供參考',
      ],
    );
  }

  Map<int, double> _frequencyProbabilities(List<MarkSixDraw> draws) {
    final counts = <int, int>{};
    for (var i = 1; i <= totalNumbers; i++) { counts[i] = 1; }
    for (final draw in draws) {
      for (final n in draw.numbers) { counts[n] = (counts[n] ?? 0) + 1; }
    }
    final total = counts.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (counts[n] ?? 1) / total};
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
    for (var n = 1; n <= totalNumbers; n++) { combined[n] = 1; }
    for (final prev in draws.last.numbers) {
      for (var n = 1; n <= totalNumbers; n++) {
        combined[n] = (combined[n] ?? 0) + (transitions[prev]![n] ?? 1);
      }
    }
    final total = combined.values.reduce((a, b) => a + b);
    return {for (var n = 1; n <= totalNumbers; n++) n: (combined[n] ?? 1) / total};
  }



  Map<int, double> _mlProbabilities(List<MarkSixDraw> draws) {
    final freq = _frequencyProbabilities(draws);
    final lastSeen = <int, int>{};
    for (var n = 1; n <= totalNumbers; n++) { lastSeen[n] = draws.length; }
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

  // ---- Self-correction ----

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
        ? history!.last.rollingAccuracy : 0.0;
    final rollingAccuracy = alpha * (matches / 6.0) + (1 - alpha) * prevAcc;

    // Self-correction: adjust weights based on performance
    if (rollingAccuracy < prevAcc - 0.05 && history != null && history.length > 10) {
      // Penalize: slightly randomize weights
      _wFreq = (_wFreq + 0.05).clamp(0.05, 0.80);
      _wMarkov = (_wMarkov - 0.03).clamp(0.05, 0.80);
      _wMl = (_wMl + 0.03).clamp(0.05, 0.80);
      final sum = _wFreq + _wMarkov + _wMl;
      _wFreq /= sum; _wMarkov /= sum; _wMl /= sum;
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
  /// Uses Isolate for background execution to avoid UI freeze.
  Future<List<MarkSixCorrection>> backtestAsync(
    List<MarkSixDraw> draws, {
    int minTraining = 100,
    void Function(int done, int total)? onProgress,
  }) async {
    final results = await Isolate.run(() => _backtestSync(draws, minTraining, onProgress));
    return results;
  }

  static List<MarkSixCorrection> _backtestSync(
    List<MarkSixDraw> draws,
    int minTraining,
    void Function(int done, int total)? onProgress,
  ) {
    final engine = MarkSixEngine();
    final results = <MarkSixCorrection>[];
    if (draws.length <= minTraining + 1) return results;
    final total = draws.length - minTraining;
    for (var i = minTraining; i < draws.length; i++) {
      final pred = engine.predict(draws.sublist(0, i));
      results.add(engine.correct(
        prediction: pred,
        actualDraw: draws[i],
        history: results,
      ));
      onProgress?.call(i - minTraining + 1, total);
    }
    return results;
  }

  List<MarkSixCorrection> backtest(
    List<MarkSixDraw> draws, {int minTraining = 100}
  ) {
    final results = <MarkSixCorrection>[];
    if (draws.length <= minTraining + 1) return results;
    for (var i = minTraining; i < draws.length; i++) {
      final pred = predict(draws.sublist(0, i));
      results.add(correct(
        prediction: pred, actualDraw: draws[i], history: results,
      ));
    }
    return results;
  }
}
