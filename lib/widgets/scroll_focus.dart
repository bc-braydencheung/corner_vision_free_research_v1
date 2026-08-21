import 'package:flutter/material.dart';

/// Brings itself into view while it is the card the user asked to see.
///
/// Tapping a pick in the summary card can only switch the league; the fixture
/// itself may sit far below the fold, so the card that was asked for reports its
/// own position once it is laid out instead of the caller guessing an offset.
class ScrollFocusTarget extends StatefulWidget {
  const ScrollFocusTarget({
    required this.focused,
    required this.child,
    super.key,
  });

  final bool focused;
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
    if (widget.focused && !oldWidget.focused) {
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
