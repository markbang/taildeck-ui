import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'l10n.dart';

/// What one press of the system back button answered, most local first.
///
/// Sheets, dialogs and popup menus are routes above the shell, so they pop
/// before any of these run.
enum BackStep {
  /// A text field had focus: back only hides the keyboard.
  keyboard,

  /// The page a tab opened over its list (node detail, terminal, a chat).
  page,

  /// Any tab but the first returns to Nodes.
  tab,

  /// Nothing left to close: ask for a second press.
  askExit,

  /// The second press inside the window leaves the app.
  exit,
}

/// Two presses inside [window] leave the app; the first only asks for another.
class ExitGuard {
  ExitGuard({
    this.window = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration window;
  final DateTime Function() _now;
  DateTime? _armed;

  bool get armed => _armed != null;

  /// True when this press exits; one outside [window] re-arms the guard.
  bool press() {
    final armed = _armed;
    final now = _now();
    if (armed != null && now.difference(armed) <= window) {
      _armed = null;
      return true;
    }
    _armed = now;
    return false;
  }

  void clear() => _armed = null;
}

/// True while the software keyboard is up, where back means "hide it".
bool keyboardVisible(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom > 0;

/// Hides the keyboard; true when there was one to hide.
bool hideKeyboard(BuildContext context) {
  if (!keyboardVisible(context)) return false;
  FocusManager.instance.primaryFocus?.unfocus();
  return true;
}

/// Shows "press back again to exit". A banner rather than a snackbar: the app
/// is a bare WidgetsApp with no ScaffoldMessenger above the pages.
void showExitHint(BuildContext context) {
  final text = AppLocalizations.of(context).backAgainToExit;
  final host = BannerHost.maybeOf(context);
  if (host != null) {
    host.show(text);
    return;
  }
  debugPrint('taildeck back: $text');
}

/// Leaves the app: Android moves the task to the background, as back does on
/// any other screen.
Future<void> leaveApp() => SystemNavigator.pop();

/// One line per press, so the emulator test can assert which way back went.
void logBack(BackStep step) => debugPrint('taildeck back: ${step.name}');
