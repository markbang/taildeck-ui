import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../motion.dart';

/// Opens [builder] as a Material 3 modal bottom sheet: it rises from the
/// bottom edge over the default spatial spring (440 ms) while the scrim fades
/// in, and leaves on the fast effects one (150 ms), as
/// `ModalBottomSheetDefaults` times it.
Future<T?> showMotionSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return Navigator.of(context).push<T>(_MotionSheetRoute<T>(builder: builder));
}

class _MotionSheetRoute<T> extends PopupRoute<T> {
  _MotionSheetRoute({required this.builder});

  final WidgetBuilder builder;

  bool get _reduceMotion {
    final anchor = navigator?.context;
    return anchor != null &&
        (MediaQuery.maybeDisableAnimationsOf(anchor) ?? false);
  }

  @override
  Duration get transitionDuration =>
      _reduceMotion ? Duration.zero : defaultSpatial.duration;

  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? Duration.zero : fadeFast.duration;

  @override
  Color get barrierColor => const Color(0x52000000);

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final scheme = context.colorScheme;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 640, maxHeight: maxHeight),
          child: Padding(
            padding: EdgeInsets.only(bottom: insets),
            child: SizedBox(
              width: double.infinity,
              child: Surface(
                color: scheme.surfaceContainerLow,
                shape: AppShape.top(AppCorner.xxl),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _DragHandle(),
                    Flexible(
                      child: SheetProvider(
                        type: SheetType.bottomSheet,
                        child: Builder(builder: builder),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_reduceMotion) return child;
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(
            CurvedAnimation(parent: animation, curve: defaultSpatial.curve),
          ),
      child: child,
    );
  }
}

/// SheetBottomTokens: 32 × 4 dp, onSurfaceVariant, above the content.
class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 6),
      child: SizedBox(
        width: 32,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colorScheme.onSurfaceVariant,
            borderRadius: const BorderRadius.all(Radius.circular(2)),
          ),
        ),
      ),
    );
  }
}
