import 'dart:math' as math;

import '../core/drbg.dart';

/// Deterministic 2D hard-disk mixer used as an in-app numerical experiment.
///
/// 49 inelastic disks sit in a box under gravity with a vibrating floor - the
/// standard granular-mixer setup, and a genuine chaotic system. Two copies are
/// evolved from initial conditions differing by [perturbation]; the separation
/// growth rate estimates the Lyapunov exponent `lambda` empirically instead of
/// taking it on faith.
///
/// A second observable, the normalised Kendall tau distance between the current
/// vertical ordering and the initial "loaded in numerical order" arrangement,
/// measures how fast the machine forgets its ordered initial condition. This is
/// the mixing-time question, and it is distinct from the divergence question:
/// chaos guarantees unpredictability, mixing guarantees uniformity.
class HardDiskEnsemble {
  HardDiskEnsemble({
    this.count = 49,
    this.width = 0.30,
    this.height = 0.40,
    this.radius = 0.0225,
    this.gravity = 9.81,
    this.restitution = 0.92,
    this.shakeAmplitude = 0.02,
    this.shakeFrequency = 12.0,
    this.dt = 5e-4,
    this.perturbation = 1e-9,
    int seed = 0x5150,
  }) {
    final rng = Drbg(<int>[seed & 0xff, (seed >> 8) & 0xff, 0x6a, 0x11]);
    _x = List<double>.filled(count, 0);
    _y = List<double>.filled(count, 0);
    _vx = List<double>.filled(count, 0);
    _vy = List<double>.filled(count, 0);

    final perRow = (width / (2.2 * radius)).floor().clamp(1, count);
    for (var i = 0; i < count; i++) {
      final row = i ~/ perRow;
      final col = i % perRow;
      _x[i] = radius * 1.1 + col * 2.2 * radius;
      _y[i] = radius * 1.1 + row * 2.2 * radius;
      _vx[i] = 0.02 * rng.nextGaussian();
      _vy[i] = 0.02 * rng.nextGaussian();
    }
    _x2 = List<double>.of(_x);
    _y2 = List<double>.of(_y);
    _vx2 = List<double>.of(_vx);
    _vy2 = List<double>.of(_vy);
    _x2[0] += perturbation;
  }

  final int count;
  final double width;
  final double height;
  final double radius;
  final double gravity;
  final double restitution;
  final double shakeAmplitude;
  final double shakeFrequency;
  final double dt;
  final double perturbation;

  late List<double> _x, _y, _vx, _vy;
  late List<double> _x2, _y2, _vx2, _vy2;

  double _t = 0;
  final List<double> _logSeparation = <double>[];
  final List<double> _times = <double>[];
  final List<double> _kendall = <double>[];

  double get time => _t;
  List<double> get x => _x;
  List<double> get y => _y;
  List<double> get logSeparation => _logSeparation;
  List<double> get times => _times;
  List<double> get kendallDistance => _kendall;

  double _floorY(double t) =>
      shakeAmplitude * math.sin(2 * math.pi * shakeFrequency * t);

  void _advance(
    List<double> px,
    List<double> py,
    List<double> pvx,
    List<double> pvy,
    double t,
  ) {
    final floor = _floorY(t);
    final floorV =
        shakeAmplitude *
        2 *
        math.pi *
        shakeFrequency *
        math.cos(2 * math.pi * shakeFrequency * t);

    for (var i = 0; i < count; i++) {
      pvy[i] -= gravity * dt;
      px[i] += pvx[i] * dt;
      py[i] += pvy[i] * dt;

      if (px[i] < radius) {
        px[i] = radius;
        pvx[i] = -pvx[i] * restitution;
      } else if (px[i] > width - radius) {
        px[i] = width - radius;
        pvx[i] = -pvx[i] * restitution;
      }
      final lowerBound = floor + radius;
      if (py[i] < lowerBound) {
        py[i] = lowerBound;
        pvy[i] = floorV + (floorV - pvy[i]) * restitution;
      } else if (py[i] > height - radius) {
        py[i] = height - radius;
        pvy[i] = -pvy[i] * restitution;
      }
    }

    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        final dx = px[j] - px[i];
        final dy = py[j] - py[i];
        final d2 = dx * dx + dy * dy;
        final minD = 2 * radius;
        if (d2 >= minD * minD || d2 == 0) continue;
        final d = math.sqrt(d2);
        final nx = dx / d;
        final ny = dy / d;
        final overlap = minD - d;
        px[i] -= nx * overlap / 2;
        py[i] -= ny * overlap / 2;
        px[j] += nx * overlap / 2;
        py[j] += ny * overlap / 2;
        final rvn = (pvx[j] - pvx[i]) * nx + (pvy[j] - pvy[i]) * ny;
        if (rvn >= 0) continue;
        final imp = -(1 + restitution) * rvn / 2;
        pvx[i] -= imp * nx;
        pvy[i] -= imp * ny;
        pvx[j] += imp * nx;
        pvy[j] += imp * ny;
      }
    }
  }

  void step([int repeats = 1]) {
    for (var s = 0; s < repeats; s++) {
      _advance(_x, _y, _vx, _vy, _t);
      _advance(_x2, _y2, _vx2, _vy2, _t);
      _t += dt;
    }
    _times.add(_t);
    _logSeparation.add(math.log(_separation()));
    _kendall.add(_kendallTauFromLoadedOrder());
  }

  double _separation() {
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      final dx = _x[i] - _x2[i];
      final dy = _y[i] - _y2[i];
      sum += dx * dx + dy * dy;
    }
    return math.max(math.sqrt(sum), 1e-300);
  }

  /// Normalised Kendall tau distance in `[0, 1]`; 0 means the balls are still in
  /// their loading order, 0.5 means the order carries no information.
  double _kendallTauFromLoadedOrder() {
    var discordant = 0;
    var total = 0;
    for (var i = 0; i < count; i++) {
      for (var j = i + 1; j < count; j++) {
        total++;
        if (_y[j] < _y[i]) discordant++;
      }
    }
    return total == 0 ? 0 : discordant / total;
  }

  /// Least-squares slope of `ln(separation)` over the pre-saturation window,
  /// i.e. the measured Lyapunov exponent in inverse seconds.
  double estimateLyapunov({double saturationFraction = 0.6}) {
    if (_logSeparation.length < 8) return double.nan;
    final maxLog = _logSeparation.reduce(math.max);
    final startLog = _logSeparation.first;
    final cutoff = startLog + saturationFraction * (maxLog - startLog);
    final xs = <double>[];
    final ys = <double>[];
    for (var i = 0; i < _logSeparation.length; i++) {
      if (_logSeparation[i] <= cutoff) {
        xs.add(_times[i]);
        ys.add(_logSeparation[i]);
      }
    }
    if (xs.length < 4) return double.nan;
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < n; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    return den == 0 ? double.nan : num / den;
  }

  /// Time at which the loading order stops carrying information (Kendall tau
  /// distance first reaching `0.5 - tolerance`), in seconds. NaN if not reached.
  double mixingTime({double tolerance = 0.05}) {
    for (var i = 0; i < _kendall.length; i++) {
      if ((_kendall[i] - 0.5).abs() < tolerance) return _times[i];
    }
    return double.nan;
  }
}
