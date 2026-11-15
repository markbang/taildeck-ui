import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/log_summary.dart';

void main() {
  test('counts lines and keeps the newest stamp', () {
    final summary = summarizeLogs(
      '14:01:03 started\n\n14:02:07 gateway up\n14:02:08 tailnet ready\n',
    );
    expect(summary.lines, 3);
    expect(summary.lastTime, '14:02');
  });

  test('an unstamped tail does not reset the stamp', () {
    final summary = summarizeLogs('09:05:00 ping\n--- app errors ---\nboom');
    expect(summary.lines, 3);
    expect(summary.lastTime, '09:05');
  });

  test('empty text has no lines and no time', () {
    final summary = summarizeLogs('\n  \n');
    expect(summary.lines, 0);
    expect(summary.lastTime, isNull);
  });
}
