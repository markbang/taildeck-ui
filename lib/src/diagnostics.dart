import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The last uncaught errors, so the logs page can show why the UI stopped.
class AppErrors extends ChangeNotifier {
  static const _limit = 40;

  final _lines = <String>[];

  List<String> get lines => List.unmodifiable(_lines);

  String get text => _lines.join('\n');

  void record(Object error, StackTrace? stack) {
    final first = stack?.toString().split('\n').take(6).join('\n') ?? '';
    _lines.add('$error${first.isEmpty ? '' : '\n$first'}');
    if (_lines.length > _limit) _lines.removeRange(0, _lines.length - _limit);
    notifyListeners();
  }

  void clear() {
    if (_lines.isEmpty) return;
    _lines.clear();
    notifyListeners();
  }
}

final appErrors = AppErrors();

/// Keeps a build error from leaving a grey box: the failure is logged for the
/// logs page and the app stays up behind a readable surface.
void installErrorHandlers() {
  FlutterError.onError = (details) {
    appErrors.record(details.exceptionAsString(), details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appErrors.record(error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => AppErrorBox(details);
}

/// What replaces a widget that failed to build: the message, in the open.
class AppErrorBox extends StatelessWidget {
  const AppErrorBox(this.details, {super.key});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final message = details.exceptionAsString();
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF1B1B1F),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '⚠',
                  style: TextStyle(color: Color(0xFFE3B341), fontSize: 28),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This part could not be drawn',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFEDEDF0),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9A9AA5),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'The details are in Logs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6E6E78), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
