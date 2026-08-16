import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:edgewise/marksix_lab/core/combinatorics.dart';
import 'package:edgewise/marksix_lab/core/drbg.dart';
import 'package:edgewise/marksix_lab/crowd/crowd_model.dart';
import 'package:edgewise/marksix_lab/crowd/optimizer.dart';
import 'package:edgewise/marksix_lab/crowd/parimutuel.dart';
import 'package:edgewise/marksix_lab/data/history_csv.dart';
import 'package:edgewise/marksix_lab/data/synthetic_history.dart';
import 'package:edgewise/marksix_lab/physics/hard_disk_ensemble.dart';
import 'package:edgewise/marksix_lab/physics/predictability.dart';
import 'package:edgewise/marksix_lab/stats/bias_audit.dart';
import 'package:edgewise/marksix_lab/stats/distributions.dart';
import 'package:edgewise/marksix_lab/stats/mixing_tests.dart';
import 'package:edgewise/marksix_lab/stats/power.dart';
import 'package:edgewise/marksix_lab/stats/rmt.dart';

void main() {
  group('distributions', () {
    test('normal CDF at known points', () {
      expect(normalCdf(0), closeTo(0.5, 1e-6));
      expect(normalCdf(1.959964), closeTo(0.975, 1e-4));
      expect(normalCdf(-3), closeTo(0.001349, 1e-4));
    });

    test('normal quantile inverts the CDF', () {
      for (final p in <double>[0.01, 0.25, 0.5, 0.9, 0.975, 0.999]) {
        expect(normalCdf(normalQuantile(p)), closeTo(p, 1e-4));
      }
    });

    test('chi-square tail at published critical values', () {
      expect(chiSquareSf(3.841, 1), closeTo(0.05, 1e-3));
      expect(chiSquareSf(65.171, 48), closeTo(0.05, 1e-3));
      expect(chiSquareSf(0, 5), closeTo(1.0, 1e-9));
    });

    test('beta quantile brackets the median', () {
      final m = betaQuantile(5, 5, 0.5);
      expect(m, closeTo(0.5, 1e-6));
      expect(betaQuantile(2, 8, 0.025), lessThan(betaQuantile(2, 8, 0.975)));
    });

    test('Poisson log pmf matches the closed form', () {
      expect(math.exp(poissonLogPmf(0, 2.5)), closeTo(math.exp(-2.5), 1e-12));
      expect(math.exp(poissonLogPmf(3, 3)), closeTo(0.22404, 1e-5));
    });
  });

  group('predictability bound', () {
    final report = computePredictability(const PredictabilityParams());

    test('positive Lyapunov exponent destroys information', () {
      expect(report.lyapunovExponent, greaterThan(0));
      expect(report.bitsDestroyedPerSecond, greaterThan(1));
    });

    test('surviving information is astronomically small', () {
      expect(report.log10InformationBits, lessThan(-100));
    });

    test('quantum noise reaches macroscopic scale within the stir', () {
      expect(report.macroTimeFromQuantum, lessThan(30));
      expect(report.log10PrecisionOverPlanck, lessThan(0));
    });

    test('a shorter stir leaves more information', () {
      final short = computePredictability(
        const PredictabilityParams(stirTime: 5),
      );
      expect(
        short.log10InformationBits,
        greaterThan(report.log10InformationBits),
      );
    });
  });

  group('hard disk ensemble', () {
    test('twin trajectories separate and the loading order is forgotten', () {
      final sim = HardDiskEnsemble(seed: 7, perturbation: 1e-9);
      for (var i = 0; i < 800; i++) {
        sim.step(20);
      }
      expect(sim.estimateLyapunov(), greaterThan(0));
      expect(sim.kendallDistance.first, lessThan(0.05));
      expect(sim.kendallDistance.last, greaterThan(0.1));
    });
  });

  group('bias audit', () {
    test('a fair synthetic machine is not flagged', () {
      final draws = SyntheticHistory.generate(draws: 1200, seed: 11);
      final report = BiasAudit.run(draws, monteCarloSamples: 400);
      expect(report.draws, 1200);
      expect(report.observations, 1200 * kPickCount);
      expect(report.monteCarloP, greaterThan(0.01));
      expect(report.klDivergence, greaterThan(0));
    });

    test('a grossly biased machine is flagged', () {
      final draws = SyntheticHistory.generate(
        draws: 2500,
        seed: 12,
        biasedBall: 17,
        relativeBias: 0.9,
      );
      final report = BiasAudit.run(draws, monteCarloSamples: 400);
      expect(report.significantAtFivePercent, isTrue);
      expect(report.extreme.number, 17);
    });

    test('posterior intervals contain the uniform rate for a fair machine', () {
      final draws = SyntheticHistory.generate(draws: 2000, seed: 13);
      final report = BiasAudit.run(draws, monteCarloSamples: 50);
      final covered = report.posteriors
          .where(
            (p) => p.lower95 <= 1 / kBallCount && p.upper95 >= 1 / kBallCount,
          )
          .length;
      expect(covered, greaterThanOrEqualTo(44));
    });
  });

  group('random matrix analysis', () {
    test('fair draws are not judged to show level repulsion', () {
      final draws = SyntheticHistory.generate(draws: 800, seed: 21);
      final report = RmtAnalysis.run(draws, monteCarloSamples: 120);
      expect(report.spacings.length, 800 * (kPickCount - 1));
      expect(report.meanSpacing, closeTo(1.0, 0.15));
      expect(report.favoursRepulsion, isFalse);
    });

    test('spacing laws are proper distributions', () {
      expect(poissonSpacingCdf(0), 0);
      expect(wignerSpacingCdf(0), 0);
      expect(poissonSpacingCdf(30), closeTo(1, 1e-9));
      expect(wignerSpacingCdf(10), closeTo(1, 1e-9));
    });

    test('spacings of a draw are its normalised gaps', () {
      final s = RmtAnalysis.spacingsOf(<int>[1, 2, 4, 8, 16, 32]);
      expect(s.length, 5);
      expect(s.reduce((a, b) => a + b), greaterThan(0));
    });
  });

  group('mixing tests', () {
    test('fair draws show no loading-order memory', () {
      final draws = SyntheticHistory.generate(draws: 1200, seed: 31);
      final report = MixingTests.run(draws, maxLag: 6, monteCarloSamples: 200);
      expect(
        report.adjacency.expectedProbability,
        closeTo(1 - nonAdjacentSubsetCount(49, 6) / kTotalCombinations, 1e-12),
      );
      expect(report.anyResidualStructure, isFalse);
    });

    test('spectral gap gives a longer mixing time as the gap closes', () {
      final slow = MixingTests.mixingTimeFromSpectralGap(
        secondEigenvalue: 0.99,
      );
      final fast = MixingTests.mixingTimeFromSpectralGap(secondEigenvalue: 0.5);
      expect(slow, greaterThan(fast));
    });
  });

  group('power analysis', () {
    test('a 5% bias needs tens of thousands of draws', () {
      final r = PowerAnalysis.forRelativeBias(relativeBias: 0.05);
      expect(r.requiredDraws, greaterThan(1e4));
      expect(r.requiredYears, greaterThan(50));
      expect(r.achievedPower, lessThan(0.8));
    });

    test('required sample size falls as the square of the effect', () {
      final a = PowerAnalysis.forRelativeBias(relativeBias: 0.02);
      final b = PowerAnalysis.forRelativeBias(relativeBias: 0.04);
      expect(a.requiredDraws / b.requiredDraws, closeTo(4, 0.3));
    });

    test('a plausible mass defect implies an undetectable bias', () {
      final bias = biasFromMassDefect(relativeMassDefect: 1e-4);
      expect(bias.abs(), lessThan(1e-3));
    });
  });

  group('crowd model and parimutuel', () {
    final model = CrowdModel();
    final scale = buildRarityScale(model, samples: 4000);

    test('birthday combinations are more popular than high spread ones', () {
      final birthday = model.logPopularity(<int>[3, 7, 12, 18, 24, 31]);
      final rare = model.logPopularity(<int>[2, 13, 29, 37, 42, 46]);
      expect(birthday, greaterThan(rare));
    });

    test('rarity percentile is monotone in unpopularity', () {
      final popular = scale.percentileForScore(
        model.logPopularity(<int>[1, 2, 3, 4, 5, 6]),
      );
      final rare = scale.percentileForScore(
        model.logPopularity(<int>[2, 13, 29, 37, 42, 46]),
      );
      expect(rare, greaterThan(popular));
    });

    test('win probability is untouched by the crowd, payout is not', () {
      final crowded = evaluateParimutuel(
        pool: 8e7,
        unitsSold: 3e7,
        crowdRatio: 4.0,
      );
      final lonely = evaluateParimutuel(
        pool: 8e7,
        unitsSold: 3e7,
        crowdRatio: 0.25,
      );
      expect(crowded.winProbability, lonely.winProbability);
      expect(lonely.expectedReturn, greaterThan(crowded.expectedReturn));
      expect(lonely.improvementRatio, greaterThan(1));
      expect(crowded.improvementRatio, lessThan(1));
    });

    test('staking is never justified', () {
      expect(
        kellyFraction(p: 1 / kTotalCombinations, netOdds: 8e6),
        lessThan(0),
      );
    });

    test('optimizer finds rarer combinations than a random pick', () {
      final optimizer = AntiCrowdOptimizer(model, scale);
      final rng = Drbg(utf8.encode('opt'));
      final results = optimizer.search(rng: rng, results: 3, iterations: 1500);
      expect(results.length, 3);
      for (final r in results) {
        expect(r.numbers.length, kPickCount);
        expect(r.rarityPercentile, greaterThan(0.9));
      }
    });

    test('optimizer respects exclusions', () {
      final optimizer = AntiCrowdOptimizer(model, scale);
      final rng = Drbg(utf8.encode('excl'));
      final results = optimizer.search(
        rng: rng,
        results: 2,
        iterations: 800,
        excluded: <int>{44, 45, 46},
      );
      for (final r in results) {
        expect(r.numbers.any((n) => n >= 44 && n <= 46), isFalse);
      }
    });
  });

  group('history csv', () {
    test('round trips draws', () {
      final draws = SyntheticHistory.generate(draws: 20, seed: 41);
      final parsed = HistoryCsv.parse(HistoryCsv.write(draws));
      expect(parsed.errors, isEmpty);
      expect(parsed.draws.length, draws.length);
      expect(parsed.draws.first.numbers, draws.first.numbers);
    });

    test('rejects malformed rows without discarding valid ones', () {
      final result = HistoryCsv.parse(
        '24/001,2024-01-02,1,2,3,4,5,6\n'
        'broken row\n'
        '24/002,2024-01-04,1,2,3,4,5,5\n'
        '24/003,2024-01-06,7,8,9,10,11,12,13\n',
      );
      expect(result.draws.length, 2);
      expect(result.errors.length, 2);
    });
  });
}
