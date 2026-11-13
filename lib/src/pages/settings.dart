import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../l10n.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets/foundation.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.theme,
    required this.floatingNavigation,
    required this.onFloatingNavigationChanged,
    required this.onToggleTheme,
    required this.tabAnimation,
    required this.onTabAnimationChanged,
    required this.onSignOut,
  });

  final TaildeckTheme theme;
  final bool floatingNavigation;
  final ValueChanged<bool> onFloatingNavigationChanged;
  final TabAnimation tabAnimation;
  final ValueChanged<TabAnimation> onTabAnimationChanged;
  final VoidCallback onSignOut;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PageBody(
      title: l10n.tabSettings,
      children: [
        SectionLabel(l10n.appearance),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.theme, style: context.listTitleStyle),
                  const SizedBox(height: 10),
                  SegmentedControl<ThemeMode>(
                    segments: [
                      (ThemeMode.system, l10n.system),
                      (ThemeMode.light, l10n.light),
                      (ThemeMode.dark, l10n.dark),
                    ],
                    value: theme.mode,
                    onChanged: (value) => theme.setMode(value),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.language, style: context.listTitleStyle),
                  const SizedBox(height: 10),
                  SegmentedControl<String>(
                    segments: [
                      ('system', l10n.system),
                      ('en', l10n.english),
                      ('zh', l10n.chinese),
                    ],
                    value: switch (theme.locale?.languageCode) {
                      'en' => 'en',
                      'zh' => 'zh',
                      _ => 'system',
                    },
                    onChanged: (value) => theme.setLocale(
                      switch (value) {
                        'en' => const Locale('en'),
                        'zh' => const Locale('zh'),
                        _ => null,
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.navigation),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.bottomBar, style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    floatingNavigation ? l10n.floatingHint : l10n.dockedHint,
                    style: context.listCaptionStyle,
                  ),
                  const SizedBox(height: 10),
                  SegmentedControl<bool>(
                    segments: [
                      (true, l10n.floating),
                      (false, l10n.docked),
                    ],
                    value: floatingNavigation,
                    onChanged: onFloatingNavigationChanged,
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.tabAnimation, style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    tabAnimation == TabAnimation.fade
                        ? l10n.fadeHint
                        : l10n.slideHint,
                    style: context.listCaptionStyle,
                  ),
                  const SizedBox(height: 10),
                  SegmentedControl<TabAnimation>(
                    segments: [
                      (TabAnimation.slide, l10n.slide),
                      (TabAnimation.fade, l10n.fade),
                    ],
                    value: tabAnimation,
                    onChanged: onTabAnimationChanged,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.session),
        GroupCard(
          dividerInset: 16,
          children: [
            PressRegion(
              onTap: onSignOut,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.signOut,
                        style: context.listTitleStyle.copyWith(color: context.colorScheme.error),
                      ),
                    ),
                    GlyphIcon(
                      Glyphs.chevronForward,
                      size: 16,
                      color: context.colorScheme.error.opacity50,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel(l10n.about),
        GroupCard(
          dividerInset: 60,
          children: [
            ListRow(
              leading: const IconBadge(Glyphs2.nodes),
              title: Text('Taildeck', style: context.listTitleStyle),
              trailing: Text('0.1.0', style: context.listCaptionStyle),
            ),
            ListRow(
              leading: const IconBadge(Glyphs2.agents),
              title: Text('prism_ui', style: context.listTitleStyle),
              trailing: Text('0.1.2', style: context.listCaptionStyle),
            ),
          ],
        ),
      ],
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.glyph, {super.key});

  final Glyph glyph;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        shape: AppShape.all(10),
      ),
      child: GlyphIcon(glyph, size: 18, color: scheme.primary),
    );
  }
}
