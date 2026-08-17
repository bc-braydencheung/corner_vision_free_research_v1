import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class Series {
  const Series({
    required this.points,
    required this.color,
    required this.label,
    this.dashed = false,
  });

  final List<Offset> points;
  final Color color;
  final String label;
  final bool dashed;
}

class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.series,
    this.height = 200,
    this.xLabel = '',
    this.yLabel = '',
    this.yMin,
    this.yMax,
  });

  final List<Series> series;
  final double height;
  final String xLabel;
  final String yLabel;
  final double? yMin;
  final double? yMax;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _LineChartPainter(
              series: series,
              yMin: yMin,
              yMax: yMax,
              xLabel: xLabel,
              yLabel: yLabel,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: series
              .map(
                (s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(width: 14, height: 3, color: s.color),
                    const SizedBox(width: 6),
                    Text(
                      s.label,
                      style: const TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.series,
    required this.xLabel,
    required this.yLabel,
    this.yMin,
    this.yMax,
  });

  final List<Series> series;
  final String xLabel;
  final String yLabel;
  final double? yMin;
  final double? yMax;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 48.0;
    const bottom = 26.0;
    const top = 10.0;
    const right = 10.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );

    final axis = Paint()
      ..color = const Color(0xFF2A2A3E)
      ..strokeWidth = 1;
    canvas.drawRect(plot, axis..style = PaintingStyle.stroke);

    final all = series.expand((s) => s.points).toList();
    if (all.isEmpty) return;
    var minX = all.map((p) => p.dx).reduce(math.min);
    var maxX = all.map((p) => p.dx).reduce(math.max);
    var minY = yMin ?? all.map((p) => p.dy).reduce(math.min);
    var maxY = yMax ?? all.map((p) => p.dy).reduce(math.max);
    if (maxX - minX < 1e-12) maxX = minX + 1;
    if (maxY - minY < 1e-12) maxY = minY + 1;
    final padY = (maxY - minY) * 0.08;
    minY -= padY;
    maxY += padY;

    Offset toPixel(Offset p) => Offset(
      plot.left + (p.dx - minX) / (maxX - minX) * plot.width,
      plot.bottom - (p.dy - minY) / (maxY - minY) * plot.height,
    );

    final grid = Paint()
      ..color = const Color(0xFF1E1E2E)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    for (final s in series) {
      if (s.points.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path();
      var started = false;
      for (final p in s.points) {
        final px = toPixel(p);
        if (!started) {
          path.moveTo(px.dx, px.dy);
          started = true;
        } else {
          path.lineTo(px.dx, px.dy);
        }
      }
      if (s.dashed) {
        _drawDashed(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }

    _text(canvas, _fmt(maxY), Offset(4, plot.top - 2), 10);
    _text(canvas, _fmt(minY), Offset(4, plot.bottom - 12), 10);
    if (yLabel.isNotEmpty) {
      _text(canvas, yLabel, Offset(4, plot.top + plot.height / 2 - 6), 10);
    }
    _text(canvas, _fmt(minX), Offset(plot.left, plot.bottom + 6), 10);
    _text(canvas, _fmt(maxX), Offset(plot.right - 34, plot.bottom + 6), 10);
    if (xLabel.isNotEmpty) {
      _text(
        canvas,
        xLabel,
        Offset(plot.left + plot.width / 2 - 20, plot.bottom + 6),
        10,
      );
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 6, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 5;
      }
    }
  }

  String _fmt(double v) {
    if (v == 0) return '0';
    final a = v.abs();
    if (a >= 1000 || a < 0.01) return v.toStringAsExponential(1);
    return v.toStringAsFixed(a < 10 ? 2 : 1);
  }

  void _text(Canvas canvas, String text, Offset at, double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: kMuted, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) => true;
}

class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.values,
    this.height = 190,
    this.labelEvery = 4,
    this.threshold,
    this.startIndex = 1,
  });

  /// One value per category, drawn as a signed bar around zero.
  final List<double> values;
  final double height;
  final int labelEvery;

  /// Optional symmetric significance threshold drawn as dashed lines.
  final double? threshold;
  final int startIndex;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarChartPainter(
          values: values,
          labelEvery: labelEvery,
          threshold: threshold,
          startIndex: startIndex,
        ),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.values,
    required this.labelEvery,
    required this.startIndex,
    this.threshold,
  });

  final List<double> values;
  final int labelEvery;
  final int startIndex;
  final double? threshold;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const bottom = 20.0;
    final plot = Rect.fromLTRB(30, 6, size.width, size.height - bottom);
    var maxAbs = values.map((v) => v.abs()).reduce(math.max);
    if (threshold != null) maxAbs = math.max(maxAbs, threshold! * 1.25);
    if (maxAbs < 1e-9) maxAbs = 1;

    final zeroY = plot.top + plot.height / 2;
    canvas.drawLine(
      Offset(plot.left, zeroY),
      Offset(plot.right, zeroY),
      Paint()..color = const Color(0xFF2A2A3E),
    );

    if (threshold != null) {
      final dash = Paint()
        ..color = kDanger.withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (final sign in <int>[-1, 1]) {
        final y = zeroY - sign * threshold! / maxAbs * plot.height / 2;
        for (var x = plot.left; x < plot.right; x += 10) {
          canvas.drawLine(Offset(x, y), Offset(x + 5, y), dash);
        }
      }
    }

    final barWidth = plot.width / values.length;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      final h = v / maxAbs * plot.height / 2;
      final rect = Rect.fromLTRB(
        plot.left + i * barWidth + barWidth * 0.18,
        v >= 0 ? zeroY - h : zeroY,
        plot.left + (i + 1) * barWidth - barWidth * 0.18,
        v >= 0 ? zeroY : zeroY - h,
      );
      final exceeded = threshold != null && v.abs() > threshold!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = exceeded ? kDanger : kAccent.withValues(alpha: 0.75),
      );
      if (i % labelEvery == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i + startIndex}',
            style: const TextStyle(color: kMuted, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(rect.center.dx - tp.width / 2, plot.bottom + 4),
        );
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: maxAbs.toStringAsFixed(1),
        style: const TextStyle(color: kMuted, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(2, plot.top));
  }

  @override
  bool shouldRepaint(covariant _BarChartPainter old) => true;
}

class HistogramWithCurves extends StatelessWidget {
  const HistogramWithCurves({
    super.key,
    required this.samples,
    required this.curves,
    this.bins = 24,
    this.maxX = 4,
    this.height = 220,
  });

  final List<double> samples;
  final List<Series> curves;
  final int bins;
  final double maxX;
  final double height;

  @override
  Widget build(BuildContext context) {
    final counts = List<double>.filled(bins, 0);
    final binWidth = maxX / bins;
    for (final s in samples) {
      if (s < 0 || s >= maxX) continue;
      counts[(s / binWidth).floor().clamp(0, bins - 1)] += 1;
    }
    final total = samples.length.toDouble();
    final density = counts
        .map((c) => total == 0 ? 0.0 : c / (total * binWidth))
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _HistogramPainter(
              density: density,
              binWidth: binWidth,
              curves: curves,
              maxX: maxX,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 12,
                  height: 10,
                  color: kAccent.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                const Text('實測', style: TextStyle(fontSize: 11, color: kMuted)),
              ],
            ),
            ...curves.map(
              (c) => Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(width: 14, height: 3, color: c.color),
                  const SizedBox(width: 6),
                  Text(
                    c.label,
                    style: const TextStyle(fontSize: 11, color: kMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistogramPainter extends CustomPainter {
  _HistogramPainter({
    required this.density,
    required this.binWidth,
    required this.curves,
    required this.maxX,
  });

  final List<double> density;
  final double binWidth;
  final List<Series> curves;
  final double maxX;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 24.0;
    final plot = Rect.fromLTRB(36, 8, size.width - 6, size.height - bottom);
    canvas.drawRect(
      plot,
      Paint()
        ..color = const Color(0xFF2A2A3E)
        ..style = PaintingStyle.stroke,
    );

    var maxY = density.isEmpty ? 1.0 : density.reduce(math.max);
    for (final c in curves) {
      for (final p in c.points) {
        maxY = math.max(maxY, p.dy);
      }
    }
    maxY *= 1.12;

    final barWidth = plot.width / density.length;
    for (var i = 0; i < density.length; i++) {
      final h = density[i] / maxY * plot.height;
      canvas.drawRect(
        Rect.fromLTRB(
          plot.left + i * barWidth,
          plot.bottom - h,
          plot.left + (i + 1) * barWidth - 1,
          plot.bottom,
        ),
        Paint()..color = kAccent.withValues(alpha: 0.35),
      );
    }

    for (final c in curves) {
      final path = Path();
      var started = false;
      for (final p in c.points) {
        final px = plot.left + p.dx / maxX * plot.width;
        final py = plot.bottom - p.dy / maxY * plot.height;
        if (!started) {
          path.moveTo(px, py);
          started = true;
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = c.color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    void label(String t, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: const TextStyle(color: kMuted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at);
    }

    label(maxY.toStringAsFixed(2), Offset(2, plot.top));
    label('0', Offset(2, plot.bottom - 10));
    label('s = 0', Offset(plot.left, plot.bottom + 6));
    label(
      's = ${maxX.toStringAsFixed(0)}',
      Offset(plot.right - 34, plot.bottom + 6),
    );
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) => true;
}
