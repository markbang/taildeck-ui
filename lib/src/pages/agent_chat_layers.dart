import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports its child's size after each layout that changes it, so a page can
/// pad a list by a floating layer's real height.
class SizeReport extends SingleChildRenderObjectWidget {
  const SizeReport({super.key, required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReport(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSizeReport).onSize = onSize;
  }
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final reported = size;
    // Layout may not rebuild; the page takes the size in the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(reported));
  }
}

/// A chat transcript's scroll controller: it opens at the newest message, and
/// while the reader is at the end it keeps the end in view when the viewport
/// shrinks (the keyboard), the floating layers grow, or [follow] is set for new
/// messages. A tool group expanding in place does not move the list.
class ChatScrollController extends ScrollController {
  bool _follow = false;

  /// Keep the end in view through the next layouts (new messages arrived).
  void follow() {
    _follow = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow = false);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _ChatScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _ChatScrollPosition extends ScrollPositionWithSingleContext {
  _ChatScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final ChatScrollController controller;

  /// Through the first frame the list holds its newest message while lazily
  /// built rows refine its extent.
  bool _opening = true;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final first = !haveDimensions;
    if (first) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _opening = false);
    }
    final applied = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (first && pixels != maxScrollExtent) {
      correctPixels(maxScrollExtent);
      return false;
    }
    return applied;
  }

  @override
  bool correctForNewDimensions(
    ScrollMetrics oldPosition,
    ScrollMetrics newPosition,
  ) {
    final atEnd = oldPosition.pixels >= oldPosition.maxScrollExtent - 1;
    final resized =
        oldPosition.viewportDimension != newPosition.viewportDimension;
    final pin =
        !activity!.isScrolling &&
        (_opening || atEnd && (resized || controller._follow));
    if (pin && newPosition.pixels != newPosition.maxScrollExtent) {
      correctPixels(newPosition.maxScrollExtent);
      return false;
    }
    return super.correctForNewDimensions(oldPosition, newPosition);
  }
}
