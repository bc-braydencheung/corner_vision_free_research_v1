import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Whether animations should run at all.
///
/// Widget tests pump a fixed number of frames, so an animation that never ends
/// would hang `pumpAndSettle`; the same switch also respects the platform's
/// reduce-motion setting instead of overriding it.
bool animationsEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

/// Fades and lifts its child in, delayed by its position in a list.
///
/// The delay is what makes a page of cards read as one movement rather than a
/// dozen unrelated ones; the child is laid out at its final size from the first
/// frame, so nothing reflows while it plays.
class StaggerIn extends StatefulWidget {
  const StaggerIn({
    required this.child,
    this.index = 0,
    this.offset = 18,
    super.key,
  });

  final Widget child;

  /// Position in the surrounding list; each step adds one [AppMotion.stagger].
  final int index;

  /// Distance in logical pixels the child rises through.
  final double offset;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (!animationsEnabled(context)) {
      _controller.value = 1;
      return;
    }
    final delay = AppMotion.stagger * widget.index.clamp(0, 12);
    Future<void>.delayed(delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Counts a number up to its value, and animates again when it changes.
///
/// The formatter owns the text, so a percentage, a price and a balance all
/// animate the same way without this widget knowing what it is showing.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    required this.value,
    required this.format,
    this.style,
    this.duration = AppMotion.slow,
    super.key,
  });

  final double value;
  final String Function(double) format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (!animationsEnabled(context)) {
      return Text(format(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => Text(format(shown), style: style),
    );
  }
}

/// A circular confidence gauge: an arc that sweeps to the value on show.
///
/// It replaces a row of numbers with one shape that can be read at a glance;
/// the number stays inside it so nothing is lost by removing the sentence that
/// used to explain it.
class ConfidenceRing extends StatelessWidget {
  const ConfidenceRing({
    required this.value,
    required this.color,
    this.label,
    this.caption,
    this.size = 62,
    super.key,
  });

  /// 0–1 confidence; values outside the range are clamped.
  final double value;
  final Color color;

  /// Big text inside the ring; defaults to the value as a percentage.
  final String? label;

  /// Small text under the label, e.g. the confidence band.
  final String? caption;
  final double size;

  @override
  Widget build(BuildContext context) {
    final target = value.clamp(0.0, 1.0);
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label ?? '${(target * 100).round()}',
          style: TextStyle(
            fontSize: size * 0.28,
            fontWeight: FontWeight.w900,
            color: color,
            height: 1.05,
          ),
        ),
        if (caption != null)
          Text(
            caption!,
            style: TextStyle(
              fontSize: size * 0.16,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
    if (!animationsEnabled(context)) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(value: target, color: color),
          child: Center(child: content),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: target),
        duration: AppMotion.slow,
        curve: Curves.easeOutCubic,
        builder: (context, shown, child) => CustomPaint(
          painter: _RingPainter(value: shown, color: color),
          child: child,
        ),
        child: Center(child: content),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.11;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.09);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (value <= 0) {
      return;
    }
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [color.withValues(alpha: 0.35), color],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * value, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

/// A rounded, tinted label. The app's smallest unit of colour.
class GlowPill extends StatelessWidget {
  const GlowPill({
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppShape.chipRadius),
        border: Border.all(color: color.withValues(alpha: 0.38)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Text(
            label,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.35,
            ),
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 10 : 12, color: color),
                const SizedBox(width: 4),
              ],
              // A verdict can be a full sentence, so it wraps instead of
              // running past the card edge; an unbounded parent (a horizontal
              // list) keeps the intrinsic width.
              if (constraints.hasBoundedWidth) Flexible(child: text) else text,
            ],
          );
        },
      ),
    );
  }
}

/// A card with a tinted gradient edge, used for every block on a page.
class GradientCard extends StatelessWidget {
  const GradientCard({
    required this.child,
    this.accent = AppPalette.violet,
    this.padding = AppShape.cardPadding,
    this.highlighted = false,
    super.key,
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  /// Draws a brighter border, used for the card a tapped pick pointed at.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.normal,
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: highlighted ? 0.24 : 0.13),
            AppPalette.surface.withValues(alpha: 0.92),
          ],
        ),
        borderRadius: BorderRadius.circular(AppShape.cardRadius),
        border: Border.all(
          color: accent.withValues(alpha: highlighted ? 0.75 : 0.24),
          width: highlighted ? 1.7 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: highlighted ? 0.22 : 0.09),
            blurRadius: highlighted ? 26 : 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Presses in slightly while touched, so every tap answers immediately.
class TapScale extends StatefulWidget {
  const TapScale({required this.child, this.onTap, super.key});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: AppMotion.quick,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Breathes a few times on appearance, marking the one thing worth acting on.
///
/// The beats are deliberately finite: a permanently repeating animation keeps
/// the whole app rendering frames forever, which costs battery and leaves the
/// page never idle.
class Pulse extends StatefulWidget {
  const Pulse({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// Whether there is anything to draw attention to.
  final bool enabled;

  static const _beats = 3;
  static const _beat = Duration(milliseconds: 1400);

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Pulse._beat * Pulse._beats,
  );

  late final Animation<double> _scale = TweenSequence<double>([
    for (var beat = 0; beat < Pulse._beats; beat++) ...[
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.035,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.035,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
    ],
  ]).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      _sync();
    }
  }

  void _sync() {
    if (widget.enabled && animationsEnabled(context)) {
      _controller.forward(from: 0);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}

/// Cross-fades and slides between pages, used by the bottom navigation.
class SectionSwitcher extends StatelessWidget {
  const SectionSwitcher({required this.index, required this.child, super.key});

  /// Section currently shown; a change replays the transition.
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.normal,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.035),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(index), child: child),
    );
  }
}
