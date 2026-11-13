import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'preview_env.dart';

class TaildeckTheme extends ChangeNotifier {
  TaildeckTheme() {
    mode = switch (previewParam('theme')?.toLowerCase()) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
  }

  final Color seed = const Color(0xFF5B6BFF);
  ThemeMode mode = ThemeMode.dark;

  /// Null follows the device locale.
  Locale? locale = switch (previewParam('lang')) {
    'en' => const Locale('en'),
    'zh' => const Locale('zh'),
    _ => null,
  };

  ThemeData get light => _build(Brightness.light);
  ThemeData get dark => _build(Brightness.dark);

  ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      style: ColorStyle.soft,
    ),
    fontFamily: 'Roboto',
    fontFamilyFallback: const ['NotoSansCJK'],
  );

  void setMode(ThemeMode value) {
    if (value == mode) return;
    mode = value;
    notifyListeners();
  }

  void setLocale(Locale? value) {
    if (value == locale) return;
    locale = value;
    notifyListeners();
  }

  void toggle() {
    mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
