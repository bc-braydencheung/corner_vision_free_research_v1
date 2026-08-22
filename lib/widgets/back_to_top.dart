import 'package:flutter/material.dart';

/// A scrollable page with a corner button that returns to its top.
///
/// A league round or race day is far taller than a screen, so scrolling back by
/// hand after opening a card is the slowest part of reading the page. The button
/// only appears once the page has actually moved, so it never covers content on
/// a page that is already at the top.
class BackToTopScroller extends StatefulWidget {
  const BackToTopScroller({required this.builder, super.key});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<BackToTopScroller> createState() => _BackToTopScrollerState();
}

class _BackToTopScrollerState extends State<BackToTopScroller> {
  final _controller = ScrollController();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final visible = _controller.hasClients && _controller.offset > 320;
    if (visible != _visible) {
      setState(() => _visible = visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.builder(context, _controller),
        Positioned(
          right: 16,
          bottom: 16,
          child: IgnorePointer(
            ignoring: !_visible,
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: FloatingActionButton.small(
                heroTag: null,
                tooltip: '回到頁頂',
                onPressed: () => _controller.animateTo(
                  0,
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                ),
                child: const Icon(Icons.arrow_upward),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
