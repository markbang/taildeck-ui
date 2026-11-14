import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'loading.dart';

/// Material 3's pull to refresh (`PullToRefreshBox`): a drag past [threshold]
/// arms the refresh, and the indicator is the 48 dp contained loading dot that
/// morphs with the pull and spins while the refresh runs.
///
/// Compose pulls the content's scroll with a nested-scroll connection; here the
/// list's own overscroll reports the same distance, so nothing else moves.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Distance pulled before a release refreshes, and half of the drag becomes
  /// that distance (`PullToRefreshDefaults.PositionalThreshold`, and the
  /// modifier's 0.5 multiplier).
  static const threshold = 80.0;
  static const _dragMultiplier = 0.5;
  static const _indicatorSize = 48.0;

  /// The spinner shows for at least this long, so a fast refresh still reads.
  static const minimumSpin = Duration(milliseconds: 600);

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh>
    with SingleTickerProviderStateMixin {
  late final _offset = AnimationController.unbounded(vsync: this);
  double _pulled = 0;
  bool _refreshing = false;
  bool _dragging = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _offset.duration = const Duration(milliseconds: 250);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (_refreshing) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _dragging = true;
    } else if (notification is OverscrollNotification) {
      final delta = -notification.overscroll;
      if (delta > 0) {
        _pulled += delta;
        _offset.value = math.min(
          _pulled * PullToRefresh._dragMultiplier,
          PullToRefresh.threshold * 1.4,
        );
      }
    } else if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      // Scrolling back up takes the pull away again.
      if (notification.scrollDelta != null && notification.scrollDelta! > 0) {
        _pulled = math.max(0, _pulled - notification.scrollDelta!);
        _offset.value = math.min(
          _pulled * PullToRefresh._dragMultiplier,
          PullToRefresh.threshold * 1.4,
        );
      }
    }
    if (notification is ScrollEndNotification && _dragging) {
      _dragging = false;
      _settle();
    }
    return false;
  }

  Future<void> _settle() async {
    if (_offset.value < PullToRefresh.threshold) {
      _pulled = 0;
      await _offset.animateTo(0, curve: Curves.easeOut);
      return;
    }
    setState(() => _refreshing = true);
    await _offset.animateTo(PullToRefresh.threshold, curve: Curves.easeOut);
    final spin = Future<void>.delayed(PullToRefresh.minimumSpin);
    try {
      await Future.wait([widget.onRefresh(), spin]);
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
        _pulled = 0;
        await _offset.animateTo(0, curve: Curves.easeOut);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRect(
                child: AnimatedBuilder(
                  animation: _offset,
                  builder: (context, _) {
                    final fraction = (_offset.value / PullToRefresh.threshold)
                        .clamp(0.0, 1.0);
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Transform.translate(
                        offset: Offset(
                          0,
                          _offset.value - PullToRefresh._indicatorSize,
                        ),
                        child: Opacity(
                          opacity: fraction,
                          child: LoadingIndicator(
                            size: PullToRefresh._indicatorSize,
                            contained: true,
                            progress: _refreshing ? null : fraction,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
