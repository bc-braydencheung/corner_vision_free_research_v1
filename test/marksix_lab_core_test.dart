import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:edgewise/marksix_lab/core/combinatorics.dart';
import 'package:edgewise/marksix_lab/core/drbg.dart';
import 'package:edgewise/marksix_lab/core/hkdf.dart';
import 'package:edgewise/marksix_lab/core/provably_fair.dart';

void main() {
  group('combinatorics', () {
    test('C(49,6) is the published number of combinations', () {
      expect(kTotalCombinations, 13983816);
      expect(binomial(49, 6), 13983816);
      expect(binomial(5, 0), 1);
      expect(binomial(5, 7), 0);
    });

    test('draw entropy is about 23.74 bits', () {
      expect(kDrawEntropyBits, closeTo(23.7365, 1e-3));
    });

    test('lnBinomial agrees with binomial for large arguments', () {
      expect(math.exp(lnBinomial(49, 6)), closeTo(13983816, 1));
      expect(
        math.exp(lnBinomial(200, 7)) / binomial(200, 7),
        closeTo(1.0, 1e-6),
      );
    });

    test('non-adjacent subsets match C(n-k+1, k)', () {
      expect(nonAdjacentSubsetCount(49, 6), binomial(44, 6));
    });
  });

  group('HKDF', () {
    test('RFC 5869 test case 1', () {
      final ikm = List<int>.filled(22, 0x0b);
      final salt = List<int>.generate(13, (i) => i);
      final info = List<int>.generate(10, (i) => 0xf0 + i);
      final okm = Hkdf.derive(ikm: ikm, salt: salt, info: info, length: 42);
      expect(
        toHex(okm),
        '3cb25f25faacd57a90434f64d0362f2a'
        '2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
        '34007208d5b887185865',
      );
    });

    test('derivation is deterministic and salt-sensitive', () {
      final a = Hkdf.derive(ikm: utf8.encode('seed'), salt: <int>[1]);
      final b = Hkdf.derive(ikm: utf8.encode('seed'), salt: <int>[1]);
      final c = Hkdf.derive(ikm: utf8.encode('seed'), salt: <int>[2]);
      expect(toHex(a), toHex(b));
      expect(toHex(a), isNot(toHex(c)));
    });
  });

  group('DRBG', () {
    test('same seed reproduces the same stream', () {
      final a = Drbg(utf8.encode('x')).nextBytes(64);
      final b = Drbg(utf8.encode('x')).nextBytes(64);
      expect(toHex(a), toHex(b));
    });

    test('nextBelow stays in range and is close to uniform', () {
      final rng = Drbg(utf8.encode('uniformity'));
      final counts = List<int>.filled(7, 0);
      const n = 70000;
      for (var i = 0; i < n; i++) {
        final v = rng.nextBelow(7);
        expect(v, inInclusiveRange(0, 6));
        counts[v]++;
      }
      // Chi-square with 6 df: 22.46 is the 0.001 critical value.
      final expected = n / 7;
      var chi2 = 0.0;
      for (final c in counts) {
        chi2 += math.pow(c - expected, 2) / expected;
      }
      expect(chi2, lessThan(22.46));
    });

    test('chooseSubset returns six distinct sorted numbers in 1..49', () {
      final rng = Drbg(utf8.encode('subset'));
      for (var i = 0; i < 500; i++) {
        final s = rng.chooseSubset(kBallCount, kPickCount);
        expect(s.length, kPickCount);
        expect(s.toSet().length, kPickCount);
        expect(s.first, greaterThanOrEqualTo(1));
        expect(s.last, lessThanOrEqualTo(kBallCount));
        final sorted = List<int>.of(s)..sort();
        expect(s, sorted);
      }
    });

    test('every ball appears with roughly equal frequency', () {
      final rng = Drbg(utf8.encode('marginals'));
      const draws = 20000;
      final counts = List<int>.filled(kBallCount + 1, 0);
      for (var i = 0; i < draws; i++) {
        for (final n in rng.chooseSubset(kBallCount, kPickCount)) {
          counts[n]++;
        }
      }
      final expected = draws * kPickCount / kBallCount;
      var chi2 = 0.0;
      for (var n = 1; n <= kBallCount; n++) {
        chi2 += math.pow(counts[n] - expected, 2) / expected;
      }
      // 48 df: 85.0 is beyond the 0.001 critical value.
      expect(chi2, lessThan(85.0));
    });

    test('gaussian samples have the right first two moments', () {
      final rng = Drbg(utf8.encode('gauss'));
      const n = 40000;
      var sum = 0.0;
      var sumSq = 0.0;
      for (var i = 0; i < n; i++) {
        final z = rng.nextGaussian();
        sum += z;
        sumSq += z * z;
      }
      expect(sum / n, closeTo(0, 0.05));
      expect(sumSq / n, closeTo(1, 0.05));
    });
  });

  group('provably fair', () {
    const recipe = DrawRecipe(
      serverSeedHex: 'a1b2c3d4e5f6',
      clientSeedHex: 'deadbeef',
      publicContext: 'block-hash:00000',
      drawLabel: '24/001',
    );

    test('commitment verifies and is tamper-evident', () {
      final commitment = ProvablyFair.commit(recipe.serverSeedHex);
      expect(
        ProvablyFair.verifyCommitment(recipe.serverSeedHex, commitment),
        isTrue,
      );
      expect(
        ProvablyFair.verifyCommitment('a1b2c3d4e5f7', commitment),
        isFalse,
      );
    });

    test('generation is reproducible from the revealed recipe', () {
      final first = ProvablyFair.generate(recipe);
      final second = ProvablyFair.generate(recipe);
      expect(second.numbers, first.numbers);
      expect(second.rerollCount, first.rerollCount);
    });

    test('changing any recipe field changes the ticket', () {
      final base = ProvablyFair.generate(recipe).numbers;
      final other = ProvablyFair.generate(
        const DrawRecipe(
          serverSeedHex: 'a1b2c3d4e5f6',
          clientSeedHex: 'deadbeef',
          publicContext: 'block-hash:00000',
          drawLabel: '24/002',
        ),
      ).numbers;
      expect(other, isNot(base));
    });

    test('rejection sampling stays reproducible', () {
      bool reject(List<int> c) => c.any((n) => n <= 31);
      final a = ProvablyFair.generate(recipe, reject: reject);
      final b = ProvablyFair.generate(recipe, reject: reject);
      expect(a.numbers, b.numbers);
      expect(a.rerollCount, b.rerollCount);
      expect(a.numbers.every((n) => n > 31), isTrue);
    });
  });
}
