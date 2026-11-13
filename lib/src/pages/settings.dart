import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
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
  });

  final TaildeckTheme theme;
  final bool floatingNavigation;
  final ValueChanged<bool> onFloatingNavigationChanged;
  final TabAnimation tabAnimation;
  final ValueChanged<TabAnimation> onTabAnimationChanged;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return PageBody(
      title: 'Settings',
      children: [
        SectionLabel('Appearance'),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: context.listTitleStyle),
                  const SizedBox(height: 10),
                  SegmentedControl<ThemeMode>(
                    segments: const [
                      (ThemeMode.system, 'System'),
                      (ThemeMode.light, 'Light'),
                      (ThemeMode.dark, 'Dark'),
                    ],
                    value: theme.mode,
                    onChanged: (value) => theme.setMode(value),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SectionLabel('Navigation'),
        GroupCard(
          dividerInset: 16,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bottom bar', style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    floatingNavigation
                        ? 'Floating dock over the content'
                        : 'Docked bar under the content',
                    style: context.listCaptionStyle,
                  ),
                  const SizedBox(height: 10),
                  SegmentedControl<bool>(
                    segments: const [
                      (true, 'Floating'),
                      (false, 'Docked'),
                    ],
                    value: floatingNavigation,
                    onChanged: onFloatingNavigationChanged,
                  ),
                  const SizedBox(height: 18),
                  Text('Tab animation', style: context.listTitleStyle),
                  const SizedBox(height: 2),
                  Text(
                    tabAnimation == TabAnimation.fade
                        ? 'Cross-fade in place'
                        : 'Slide between pages',
                    style: context.listCaptionStyle,
                  ),
                  const SizedBox(height: 10),
                  SegmentedControl<TabAnimation>(
                    segments: const [
                      (TabAnimation.slide, 'Slide'),
                      (TabAnimation.fade, 'Fade'),
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
        SectionLabel('About'),
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
