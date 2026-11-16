import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../l10n.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/foundation.dart';
import '../widgets/select_row.dart';
import '../widgets/theme_preview.dart';

/// The theme page, laid out as FlClash's: the theme as it draws the app on
/// top, the mode choices below it, then the navigation choices.
class ThemePage extends StatelessWidget {
  const ThemePage({
    super.key,
    required this.theme,
    required this.floatingNavigation,
    required this.onFloatingNavigationChanged,
    required this.tabAnimation,
    required this.onTabAnimationChanged,
  });

  final TaildeckTheme theme;
  final bool floatingNavigation;
  final ValueChanged<bool> onFloatingNavigationChanged;
  final TabAnimation tabAnimation;
  final ValueChanged<TabAnimation> onTabAnimationChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final light = theme.light.colorScheme;
    final dark = theme.dark.colorScheme;
    final lightScreen = MiniScreen(colorScheme: light);
    final darkScreen = MiniScreen(colorScheme: dark);
    return Surface(
      color: SurfaceLevel.page.colorOf(context.colorScheme),
      child: PageBody(
        title: l10n.theme,
        leading: IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const GlyphIcon(Glyphs.chevronBack),
          tooltip: l10n.back,
        ),
        children: [
          ThemePreview(floatingBar: floatingNavigation),
          const SizedBox(height: 24),
          SectionLabel(l10n.themeMode, glyph: Glyphs2.sun),
          PreviewChoiceGroup<ThemeMode>(
            value: theme.mode,
            onChanged: theme.setMode,
            choices: [
              PreviewChoice(
                value: ThemeMode.system,
                label: l10n.auto,
                pictogram: MiniScreenThumb(
                  screen: MiniSplitScreen(light: lightScreen, dark: darkScreen),
                ),
              ),
              PreviewChoice(
                value: ThemeMode.light,
                label: l10n.light,
                pictogram: MiniScreenThumb(screen: lightScreen),
              ),
              PreviewChoice(
                value: ThemeMode.dark,
                label: l10n.dark,
                pictogram: MiniScreenThumb(screen: darkScreen),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SectionLabel(l10n.navigation, glyph: Glyphs2.sliders),
          generateGroup([
            SelectRow<bool>(
              label: l10n.bottomBar,
              subtitle: floatingNavigation
                  ? l10n.floatingHint
                  : l10n.dockedHint,
              value: floatingNavigation,
              options: [(true, l10n.floating), (false, l10n.docked)],
              onChanged: onFloatingNavigationChanged,
            ),
            SelectRow<TabAnimation>(
              label: l10n.tabAnimation,
              subtitle: tabAnimation == TabAnimation.fade
                  ? l10n.fadeHint
                  : l10n.slideHint,
              value: tabAnimation,
              options: [
                (TabAnimation.slide, l10n.slide),
                (TabAnimation.fade, l10n.fade),
              ],
              onChanged: onTabAnimationChanged,
            ),
          ]),
          if (context.disableAnimations) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(l10n.motionHint, style: context.listCaptionStyle),
            ),
          ],
        ],
      ),
    );
  }
}
