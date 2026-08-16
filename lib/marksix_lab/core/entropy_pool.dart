import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'provably_fair.dart';

/// Physical entropy harvested from the user's device during the ritual.
///
/// The seed material is real: pointer coordinates, pressure, and above all the
/// microsecond-scale jitter of event arrival times, which is driven by thermal
/// noise in the oscillator and by OS scheduling. The narrative around it
/// ("observer collapse") is decoration; the entropy is not.
class EntropyPool {
  final List<int> _bytes = <int>[];
  final List<int> _timingLowBits = <int>[];
  int? _lastMicros;
  String? _seedHex;

  int get sampleCount => _timingLowBits.length;

  void addSample({
    required int micros,
    double x = 0,
    double y = 0,
    double pressure = 0,
  }) {
    final delta = _lastMicros == null ? 0 : micros - _lastMicros!;
    _lastMicros = micros;

    final buffer = ByteData(24);
    // Two 32-bit halves: dart2js has no 64-bit integer accessor.
    buffer.setUint32(0, (micros ~/ 0x100000000) & 0xffffffff);
    buffer.setUint32(4, micros & 0xffffffff);
    buffer.setFloat32(8, x);
    buffer.setFloat32(12, y);
    buffer.setFloat32(16, pressure);
    buffer.setUint32(20, delta & 0xffffffff);
    _bytes.addAll(buffer.buffer.asUint8List());
    _timingLowBits.add(delta & 0x3f);
    _seedHex = null;
  }

  void addExternal(List<int> data) {
    _bytes.addAll(data);
    _seedHex = null;
  }

  /// Shannon entropy of the observed 6-bit timing-jitter histogram, in bits.
  ///
  /// A plug-in estimate of a finite sample is biased upward, so the
  /// Miller-Madow correction `(K - 1) / (2 n)` is subtracted per sample. This is
  /// deliberately conservative: it measures only timing jitter and ignores the
  /// spatial channel.
  double estimatedEntropyBits() {
    if (_timingLowBits.length < 2) return 0;
    final counts = <int, int>{};
    for (final v in _timingLowBits) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final n = _timingLowBits.length;
    var h = 0.0;
    for (final c in counts.values) {
      final p = c / n;
      h -= p * (math.log(p) / math.ln2);
    }
    final corrected = h - (counts.length - 1) / (2 * n * math.ln2);
    return math.max(0.0, corrected) * n;
  }

  /// Condense the pool to a 32-byte seed. Hashing is entropy-preserving and
  /// removes any structure in the raw samples.
  ///
  /// The digest is a pure function of the collected samples (which already
  /// carry microsecond timestamps) and is memoised until the pool changes, so
  /// the seed shown to the user is the seed a ticket is generated from.
  String seedHex() =>
      _seedHex ??= toHex(sha256.convert(List<int>.of(_bytes)).bytes);

  void clear() {
    _bytes.clear();
    _timingLowBits.clear();
    _lastMicros = null;
    _seedHex = null;
  }
}
