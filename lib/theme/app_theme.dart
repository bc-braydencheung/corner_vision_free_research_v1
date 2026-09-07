import 'package:flutter/material.dart';

/// The app's colour vocabulary.
///
/// One place owns every accent so a card, a chip and a chart cannot drift into
/// three different greens, and so the palette can be rotated per card index
/// without each widget inventing its own colour.
class AppPalette {
  const AppPalette._();

  /// Page background, darkest first.
  static const backdropTop = Color(0xFF1A1146);
  static const backdropMiddle = Color(0xFF120E33);
  static const backdropBottom = Color(0xFF07061A);

  /// Card fills, drawn over the backdrop.
  static const surface = Color(0xFF191539);
  static const surfaceHigh = Color(0xFF221C4D);

  static const violet = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const mint = Color(0xFF34E5A0);
  static const lime = Color(0xFFA3E635);
  static const amber = Color(0xFFFFB020);
  static const pink = Color(0xFFFF5FA2);
  static const coral = Color(0xFFFF7A59);
  static const slate = Color(0xFF8E8CA8);

  /// Accents cycled through lists, so a long page stays lively.
  static const rotation = <Color>[violet, cyan, mint, pink, amber, lime];

  static Color forIndex(int index) => rotation[index % rotation.length];

  /// Verdict colours: the strongest accent is reserved for a cleared pick.
  static const recommend = mint;
  static const watch = slate;
  static const warn = amber;
  static const staked = cyan;

  /// Confidence colour, so the ring, the chip and the badge always agree.
  static Color confidence(String label) => switch (label) {
    '高' => mint,
    '中' => amber,
    _ => violet,
  };
}

/// Shared corner radii and paddings, so cards stay one family.
class AppShape {
  const AppShape._();

  static const cardRadius = 26.0;
  static const tileRadius = 20.0;
  static const chipRadius = 999.0;
  static const cardPadding = EdgeInsets.fromLTRB(16, 16, 16, 16);
}

/// Motion durations used across the app, kept short enough to stay usable.
class AppMotion {
  const AppMotion._();

  static const quick = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 620);

  /// Delay between two neighbouring items of a staggered list.
  static const stagger = Duration(milliseconds: 55);
}

ThemeData buildAppTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppPalette.violet,
        brightness: Brightness.dark,
        surface: AppPalette.surface,
      ).copyWith(
        primary: AppPalette.violet,
        secondary: AppPalette.cyan,
        tertiary: AppPalette.mint,
        surfaceContainerHighest: AppPalette.surfaceHigh,
      );
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'sans-serif',
    scaffoldBackgroundColor: AppPalette.backdropBottom,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppPalette.surface.withValues(alpha: 0.94),
      indicatorColor: AppPalette.violet.withValues(alpha: 0.28),
      elevation: 0,
      height: 66,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      selectedColor: AppPalette.violet.withValues(alpha: 0.3),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 18),
        textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppPalette.cyan,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppPalette.surfaceHigh,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

/// The page backdrop: a multi-colour wash that drifts into place once.
///
/// The drift is deliberately slow, low contrast and finite — it should read as
/// depth behind the cards, and a forever-repeating gradient would keep the app
/// rendering frames for no benefit.
class AuroraBackdrop extends StatefulWidget {
  const AuroraBackdrop({required this.child, this.animate = true, super.key});

  final Widget child;

  /// Turned off for reduced-motion users.
  final bool animate;

  @override
  State<AuroraBackdrop> createState() => _AuroraBackdropState();
}

class _AuroraBackdropState extends State<AuroraBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-1 + t * 0.6, -1),
              end: Alignment(1, 1 - t * 0.5),
              colors: const [
                AppPalette.backdropTop,
                AppPalette.backdropMiddle,
                AppPalette.backdropBottom,
              ],
              stops: [0, 0.42 + t * 0.1, 1],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
