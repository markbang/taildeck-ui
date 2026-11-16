import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

/// The bar a page shows over its content: a circular back button, one line of
/// title with an optional subtitle under it, and the page's actions at its
/// end. [PageHeader] floats it, so the content scrolls under it as FlClash's
/// pages do.
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleStyle,
    this.onBack,
    this.trailing,
    this.maxWidth = 720,
  });

  final String title;
  final String? subtitle;
  final TextStyle? subtitleStyle;

  /// Draws the bar's leading button; null for a first-level page, whose bar
  /// carries the title alone.
  final VoidCallback? onBack;

  final Widget? trailing;

  /// The page body's own cap, so the bar lines up with the content under it.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final back = onBack;
    final subtitle = this.subtitle;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          height: pageToolbarHeight,
          // A filled circle behind the bar's buttons, as FlClash's bar has.
          child: TonalButtonTheme(
            glass: LiquidGlassScope.of(context),
            child: Row(
              children: [
                if (back != null) ...[
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: back,
                    icon: GlyphIcon(Glyphs.backFor(Theme.of(context).platform)),
                    tooltip: l10n.back,
                  ),
                  const SizedBox(width: 16),
                ] else
                  const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.headline.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                subtitleStyle ??
                                AppTextStyle.footnote
                                    .of(context)
                                    .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing case final trailing?) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [PageBar] floating over the content it belongs to, on a translucent
/// material that starts at the page's colour and eases out below the bar, so
/// rows read through it as they scroll past.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.child, this.collapse = 1});

  final Widget child;

  /// 0 keeps the bar out of the way of a first-level page's large title, 1
  /// draws it at rest; the page drives it from its scroll.
  final double collapse;

  /// How much of the large title is left once the bar has come this far: it
  /// goes before the bar's own title arrives, so the page never reads as two.
  static double largeTitleOpacity(double collapse) =>
      (1 - collapse / _handover).clamp(0, 1);

  /// How much of the bar's own title is in; the second half of the handover.
  static double barTitleOpacity(double collapse) =>
      ((collapse - _handover) / (1 - _handover)).clamp(0, 1);

  static const _handover = 0.65;
  static const _overhang = 16.0;
  static const _steps = 8;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final height = top + pageToolbarHeight;
    return Offstage(
      offstage: collapse <= 0,
      child: IgnorePointer(
        ignoring: collapse < 0.5,
        child: ExcludeFocus(
          excluding: collapse < 0.5,
          child: ExcludeSemantics(
            excluding: collapse < 0.5,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: -_overhang,
                  child: IgnorePointer(
                    child: _Scrim(
                      color: SurfaceLevel.page.colorOf(context.colorScheme),
                      opacity: _materialOpacity(collapse),
                      fadeStart: top / height,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: top),
                  child: Opacity(
                    opacity: barTitleOpacity(collapse),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The material fades in with the scroll, then holds a tenth of the page
  /// through it as FlClash's bar does.
  static double _materialOpacity(double collapse) =>
      0.9 * Curves.easeInOut.transform(collapse.clamp(0, 1));
}

class _Scrim extends StatelessWidget {
  const _Scrim({
    required this.color,
    required this.opacity,
    required this.fadeStart,
  });

  final Color color;
  final double opacity;
  final double fadeStart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(constraints.maxHeight, 1);
        final start = (height - PageHeader._overhang) * fadeStart / height;
        final stops = <double>[0];
        final colors = <Color>[color.withValues(alpha: opacity)];
        for (var step = 0; step <= PageHeader._steps; step++) {
          final t = step / PageHeader._steps;
          stops.add(start + (1 - start) * t);
          colors.add(
            color.withValues(
              alpha: opacity * (1 - Curves.easeInOut.transform(t)),
            ),
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: stops,
              colors: colors,
            ),
          ),
        );
      },
    );
  }
}
