import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'hkdf.dart';

/// Deterministic random bit generator in HMAC-SHA256 counter mode.
///
/// Every draw of a bounded integer uses rejection sampling, so the output is
/// exactly uniform. A plain `% n` would introduce modulo bias of order
/// `n / 2^32`, which for n = 49 skews the low numbers by ~1e-8 per call and is
/// the single most common defect in lottery-number generators.
class Drbg {
  Drbg(List<int> seed) : _key = Uint8List.fromList(seed);

  factory Drbg.fromMaterial({
    required List<int> ikm,
    List<int> salt = const <int>[],
    List<int> info = const <int>[],
  }) => Drbg(Hkdf.derive(ikm: ikm, salt: salt, info: info));

  final Uint8List _key;
  int _counter = 0;
  Uint8List _block = Uint8List(0);
  int _blockOffset = 0;

  void _refill() {
    final c = _counter++;
    final counterBytes = Uint8List(8);
    // Written as two 32-bit halves: dart2js has no 64-bit integer accessor.
    ByteData.view(counterBytes.buffer)
      ..setUint32(0, (c ~/ 0x100000000) & 0xffffffff)
      ..setUint32(4, c & 0xffffffff);
    _block = Uint8List.fromList(Hmac(sha256, _key).convert(counterBytes).bytes);
    _blockOffset = 0;
  }

  int nextByte() {
    if (_blockOffset >= _block.length) _refill();
    return _block[_blockOffset++];
  }

  Uint8List nextBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = nextByte();
    }
    return out;
  }

  int nextUint32() {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      v = (v << 8) | nextByte();
    }
    return v;
  }

  /// Uniform integer in `[0, bound)` via rejection sampling (no modulo bias).
  int nextBelow(int bound) {
    if (bound <= 0) throw ArgumentError.value(bound, 'bound', 'must be > 0');
    if (bound == 1) return 0;
    const range = 0x100000000;
    final limit = range - (range % bound);
    while (true) {
      final v = nextUint32();
      if (v < limit) return v % bound;
    }
  }

  double nextDouble() => nextUint32() / 0x100000000;

  /// Box-Muller standard normal.
  double nextGaussian() {
    final u1 = 1.0 - nextDouble();
    final u2 = nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  /// Partial Fisher-Yates: uniform `k`-subset of `1..n`, returned sorted.
  List<int> chooseSubset(int n, int k) {
    if (k < 0 || k > n) throw ArgumentError('k must be in [0, n]');
    final pool = List<int>.generate(n, (i) => i + 1);
    for (var i = 0; i < k; i++) {
      final j = i + nextBelow(n - i);
      final tmp = pool[i];
      pool[i] = pool[j];
      pool[j] = tmp;
    }
    final picked = pool.sublist(0, k)..sort();
    return picked;
  }
}
