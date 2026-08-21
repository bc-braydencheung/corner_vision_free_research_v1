import 'package:flutter/material.dart';

/// Whether a card the user navigated to has to open itself again.
///
/// Both the fixture card and the race card collapse to their verdict, so a pick
/// only lands somewhere readable if the card reopens. The user may have
/// collapsed it by hand after the first tap, which is why an unchanged target
/// with a newer request still counts as a fresh navigation.
bool shouldReopenForFocus({
  required bool focused,
  required bool wasFocused,
  required int request,
  required int previousRequest,
}) => focused && (!wasFocused || request != previousRequest);

/// Brings itself into view when it is the card the user asked to see.
///
/// Tapping a pick in the summary card can only switch the league; the fixture
/// itself may sit far below the fold, so the card that was asked for reports its
/// own position once it is laid out instead of the caller guessing an offset.
///
/// [request] is what makes the *same* card answer a second tap: asking for a
/// fixture that is already the focused one leaves [focused] unchanged, so the
/// caller bumps its request counter instead and every tap is honoured.
class ScrollFocusTarget extends StatefulWidget {
  const ScrollFocusTarget({
    required this.focused,
    required this.child,
    this.request = 0,
    super.key,
  });

  final bool focused;

  /// Increases once per navigation request, whatever the target.
  final int request;
  final Widget child;

  @override
  State<ScrollFocusTarget> createState() => _ScrollFocusTargetState();
}

class _ScrollFocusTargetState extends State<ScrollFocusTarget> {
  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(ScrollFocusTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused &&
        (!oldWidget.focused || widget.request != oldWidget.request)) {
      _reveal();
    }
  }

  void _reveal() {
    if (!widget.focused) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || Scrollable.maybeOf(context) == null) {
        return;
      }
      Scrollable.ensureVisible(
        context,
        alignment: 0.12,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
