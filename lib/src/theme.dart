import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

class TaildeckTheme extends ChangeNotifier {
  TaildeckTheme() {
    mode = switch (Uri.base.queryParameters['theme']?.toLowerCase()) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.dark,
    };
  }

  final Color seed = const Color(0xFF5B6BFF);
  ThemeMode mode = ThemeMode.dark;

  ThemeData get light => _build(Brightness.light);
  ThemeData get dark => _build(Brightness.dark);

  ThemeData _build(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      style: ColorStyle.soft,
    ),
  );

  void setMode(ThemeMode value) {
    if (value == mode) return;
    mode = value;
    notifyListeners();
  }

  void toggle() {
    mode = mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}
