import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../l10n.dart';

/// One choice of a [PreviewChoiceGroup], drawn by [pictogram].
class PreviewChoice<T> {
  const PreviewChoice({
    required this.value,
    required this.label,
    required this.pictogram,
  });

  final T value;
  final String label;
  final Widget pictogram;
}

/// Rows of choices, each holding a thumbnail of what it draws and a check when
/// picked, as FlClash's theme mode rows do.
class PreviewChoiceGroup<T> extends StatelessWidget {
  const PreviewChoiceGroup({
    super.key,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final List<PreviewChoice<T>> choices;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return generateGroup([
      for (final choice in choices)
        Semantics(
          inMutuallyExclusiveGroup: true,
          selected: choice.value == value,
          button: true,
          label: choice.label,
          excludeSemantics: true,
          child: DecorationListItem(
            leading: ExcludeSemantics(child: choice.pictogram),
            title: Text(choice.label),
            trailing: choice.value == value ? const SelectionCheck() : null,
            isSelected: choice.value == value,
            onPressed: () => onChanged(choice.value),
          ),
        ),
    ]);
  }
}

/// The current theme drawn as a phone-shaped sketch of the app's pages.
class ThemePreview extends StatelessWidget {
  const ThemePreview({super.key, required this.floatingBar});

  final bool floatingBar;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.themePreview,
      image: true,
      child: Card(
        radius: AppCorner.xxl,
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 168,
            child: AspectRatio(
              aspectRatio: 9 / 17,
              child: ClipRSuperellipse(
                borderRadius: AppRadius.all(28),
                child: TweenAnimationBuilder<ColorScheme>(
                  tween: _ColorSchemeTween(end: context.colorScheme),
                  duration: context.motionDuration(
                    const Duration(milliseconds: 300),
                  ),
                  builder: (_, colorScheme, _) => MiniScreen(
                    colorScheme: colorScheme,
                    floatingBar: floatingBar,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSchemeTween extends Tween<ColorScheme> {
  _ColorSchemeTween({super.end});

  @override
  ColorScheme lerp(double t) => ColorScheme.lerp(begin!, end!, t);
}

/// A phone-shaped sketch of the home page, drawn from its width so it fits
/// the preview and a row's thumbnail alike.
class MiniScreen extends StatelessWidget {
  const MiniScreen({
    super.key,
    required this.colorScheme,
    this.floatingBar = true,
    this.selected = 0,
  });

  final ColorScheme colorScheme;
  final bool floatingBar;

  /// Which of the four destinations the dock marks.
  final int selected;

  @override
  Widget build(BuildContext context) {
    final scheme = colorScheme;
    final page = SurfaceLevel.page.colorOf(scheme);
    final card = SurfaceLevel.card.colorOf(scheme);
    final dock = SurfaceLevel.floatingOf(scheme).colorOf(scheme);
    final ink = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = constraints.maxWidth / 20;
        final barHeight = floatingBar ? unit * 4.4 : unit * 5.2;
        final barTop =
            constraints.maxHeight -
            (floatingBar ? unit * 1.6 : 0) -
            barHeight;
        // The cards the sketch has room for above its dock, so a thumbnail
        // shows its foot without a row running under the bar.
        var top = unit * 5.2;
        final cards = <Widget>[];
        for (final rows in const [3, 2, 2]) {
          final height = unit * (2 * 0.9 + rows * 1.6 + (rows - 1) * 1.0) + 1;
          if (top + height > barTop - unit) break;
          cards.add(
            Positioned(
              top: top,
              left: unit * 1.5,
              right: unit * 1.5,
              height: height,
              child: _MiniCard(
                color: card,
                unit: unit,
                rows: rows,
                tint: scheme.primary,
                ink: ink,
                muted: muted,
              ),
            ),
          );
          top += height + unit * 1.4;
        }
        return ColoredBox(
          color: page,
          child: Stack(
            children: [
              Positioned(
                top: unit * 2,
                left: unit * 1.5,
                child: _Line(width: unit * 8, height: unit * 1.1, color: ink),
              ),
              Positioned(
                top: unit * 3.9,
                left: unit * 1.5,
                child: _Line(
                  width: unit * 4.5,
                  height: unit * 0.6,
                  color: muted.withValues(alpha: 0.6),
                ),
              ),
              ...cards,
              Positioned(
                left: floatingBar ? unit * 2 : 0,
                right: floatingBar ? unit * 2 : 0,
                top: barTop,
                height: barHeight,
                child: Container(
                  decoration: ShapeDecoration(color: dock, shape: AppShape.full),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final (index, glyph) in const [
                        Glyphs2.nodes,
                        Glyphs2.grid,
                        Glyphs2.agents,
                        Glyphs2.sliders,
                      ].indexed)
                        GlyphIcon(
                          glyph,
                          size: unit * 2.1,
                          color: index == selected ? scheme.primary : muted,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: color,
        shape: AppShape.all(height / 2),
      ),
    );
  }
}

/// A sketch of a group card: rows of an icon dot and two lines.
class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.color,
    required this.unit,
    required this.rows,
    required this.tint,
    required this.ink,
    required this.muted,
  });

  final Color color;
  final double unit;
  final int rows;
  final Color tint;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: unit * 1.2,
        vertical: unit * 0.9,
      ),
      decoration: ShapeDecoration(
        color: color,
        shape: AppShape.all(unit * 1.6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var row = 0; row < rows; row++) ...[
            if (row > 0) SizedBox(height: unit * 1),
            Row(
              children: [
                Container(
                  width: unit * 1.5,
                  height: unit * 1.5,
                  decoration: ShapeDecoration(
                    color: tint.withValues(alpha: 0.28),
                    shape: const CircleBorder(),
                  ),
                ),
                SizedBox(width: unit * 1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Line(
                        width: unit * 7,
                        height: unit * 0.7,
                        color: ink.withValues(alpha: 0.8),
                      ),
                      SizedBox(height: unit * 0.4),
                      _Line(
                        width: unit * 4.5,
                        height: unit * 0.5,
                        color: muted.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A choice's thumbnail: the foot of a [MiniScreen], as FlClash shows it.
class MiniScreenThumb extends StatelessWidget {
  const MiniScreenThumb({super.key, required this.screen});

  static const Size screenSize = Size(96, 128);
  static const double _shownHeight = 66;
  static const double _height = 30;

  /// The width the thumbnail takes in a row, for a divider that lines up
  /// with the row's label.
  static double get width => _height * screenSize.width / _shownHeight;

  final Widget screen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      width: width,
      child: ClipRSuperellipse(
        borderRadius: AppRadius.sm,
        child: FittedBox(
          child: SizedBox(
            width: screenSize.width,
            height: _shownHeight,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.bottomCenter,
                minHeight: screenSize.height,
                maxHeight: screenSize.height,
                child: screen,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Light and dark side by side, cut on a diagonal, for the mode that follows
/// the system.
class MiniSplitScreen extends StatelessWidget {
  const MiniSplitScreen({super.key, required this.light, required this.dark});

  final Widget light;
  final Widget dark;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        light,
        ClipPath(clipper: _DiagonalClipper(), child: dark),
      ],
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.3, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}
