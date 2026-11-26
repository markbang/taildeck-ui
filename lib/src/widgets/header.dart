import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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
                                opacity: _largeAlpha(compact),
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
                                opacity: _compactAlpha(compact),
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

  /// The titles cross at 0.31 of the handover: each is a power of its share of
  /// the collapse, (1 - p)^1.7 and p^1.7, so both are 0.5^1.7 at p = 0.5. The
  /// bar is never blank, and the two never both show at strength.
  static double _largeAlpha(double collapse) =>
      math.pow(1 - collapse, 1.7).toDouble();

  static double _compactAlpha(double collapse) =>
      math.pow(collapse, 1.7).toDouble();
}

/// [PageBar] floating over the content it belongs to, on a translucent
/// material that starts at the page's colour and eases out below the bar, so
/// rows read through it as they scroll past.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.child,
    this.collapse = 1,
    this.frosted = false,
  });

  final Widget child;

  /// 0 draws the bar with no material over a first-level page's content, 1
  /// draws it at rest as a subpage has it; the page drives it from its scroll.
  final double collapse;

  /// A [Frost] that ends at the bar's edge instead of a material easing out
  /// below it: the content reads through, blurred, and no band lies past the
  /// bar.
  final bool frosted;

  static const _overhang = 16.0;
  static const _steps = 8;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (frosted)
          const Positioned.fill(child: IgnorePointer(child: Frost()))
        else
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

/// The layer a page keeps at its foot (a chat's task strip and composer), on
/// the same [Frost] as a frosted [PageHeader]: the content scrolls under it
/// and is never cut at its edge. [child] takes the system gesture area as its
/// own bottom padding, so the frost runs to the screen's edge.
class PageFooter extends StatelessWidget {
  const PageFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: IgnorePointer(child: Frost())),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom,
          ),
          child: child,
        ),
      ],
    );
  }
}

/// The page's colour over a blur of what lies behind, clipped to its own box.
class Frost extends StatelessWidget {
  const Frost({super.key});

  static const sigma = 16.0;

  /// High enough that a line of text under it reads as a shade, not a glyph,
  /// and the bar keeps the page's colour in both themes.
  static const tint = 0.75;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: ColoredBox(
          color: SurfaceLevel.page
              .colorOf(context.colorScheme)
              .withValues(alpha: tint),
        ),
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.color, required this.opacity});

  final Color color;
  final double opacity;

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
