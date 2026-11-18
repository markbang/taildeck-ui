import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

/// The bar a page shows over its content: a circular back button (a subpage),
/// the page's title with an optional caption under it, and the page's actions
/// at its end. [PageHeader] floats it, so the content scrolls under it.
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleStyle,
    this.onBack,
    this.trailing,
    this.maxWidth = 720,
    this.collapse = 1,
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

  /// 0 gives a first-level page FlClash's page title at rest, 1 the compact
  /// title it keeps once the list has scrolled under the bar.
  final double collapse;

  /// The title's line box, held at the larger title's height so the swap
  /// never moves the bar or its caption.
  static const _titleBox = 30.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final back = onBack;
    final subtitle = this.subtitle;
    final compact = collapse.clamp(0.0, 1.0);
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
                      SizedBox(
                        height: _titleBox,
                        child: Stack(
                          alignment: AlignmentDirectional.centerStart,
                          children: [
                            // FlClash's page title at rest, the compact one
                            // once the list has scrolled.
                            if (compact < 1)
                              Opacity(
                                opacity: 1 - _swap(compact),
                                child: Semantics(
                                  header: compact < 0.5,
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyle.pageTitle.of(context),
                                  ),
                                ),
                              ),
                            if (compact > 0)
                              Opacity(
                                opacity: _swap(compact),
                                child: Semantics(
                                  header: compact >= 0.5,
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
                              ),
                          ],
                        ),
                      ),
                      if (subtitle != null)
                        Opacity(
                          opacity: 1 - compact,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                subtitleStyle ??
                                AppTextStyle.subheadline
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

  /// The compact title comes in over the second half of the collapse, once
  /// the larger one has gone.
  static double _swap(double collapse) =>
      ((collapse - 0.5) / 0.5).clamp(0.0, 1.0);
}

/// [PageBar] floating over the content it belongs to, on a translucent
/// material that starts at the page's colour and eases out below the bar, so
/// rows read through it as they scroll past.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.child, this.collapse = 1});

  final Widget child;

  /// 0 draws the bar with no material over a first-level page's content, 1
  /// draws it at rest as a subpage has it; the page drives it from its scroll.
  final double collapse;

  static const _overhang = 16.0;
  static const _steps = 8;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
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
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: top),
          child: child,
        ),
      ],
    );
  }

  /// The material fades in with the scroll and then holds the bar's own
  /// colour, so a row never reads through the title.
  static double _materialOpacity(double collapse) =>
      _material * Curves.easeInOut.transform(collapse.clamp(0, 1));

  static const _material = 0.97;
}

/// The layer a page keeps at its foot (a chat's task strip and composer): the
/// page's colour, solid behind [child] and easing out above it as
/// [PageHeader] eases out below, so the content scrolls under it instead of
/// being cut at its edge.
class PageFooter extends StatelessWidget {
  const PageFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: -PageHeader._overhang,
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: _Scrim(
              color: SurfaceLevel.page.colorOf(context.colorScheme),
              opacity: 1,
              fadeUp: true,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({
    required this.color,
    required this.opacity,
    this.fadeUp = false,
  });

  final Color color;
  final double opacity;

  /// Fades out towards the top edge (a footer) instead of the bottom.
  final bool fadeUp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.max(constraints.maxHeight, 1);
        final solid = (height - PageHeader._overhang) / height;
        final stops = <double>[0, solid];
        final colors = <Color>[
          color.withValues(alpha: opacity),
          color.withValues(alpha: opacity),
        ];
        for (var step = 0; step <= PageHeader._steps; step++) {
          final t = step / PageHeader._steps;
          stops.add(solid + (1 - solid) * t);
          colors.add(
            color.withValues(
              alpha: opacity * (1 - Curves.easeInOut.transform(t)),
            ),
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fadeUp ? Alignment.bottomCenter : Alignment.topCenter,
              end: fadeUp ? Alignment.topCenter : Alignment.bottomCenter,
              stops: stops,
              colors: colors,
            ),
          ),
        );
      },
    );
  }
}
