@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Run 44438129087: the focus ANR killed the app while wait_home was still
// waiting, and the gate failed with "the shell did not settle" and no verdict.
const _fixture = 'test/fixtures/back_anr_44438129087.txt';

// Run 44445470776: an ANR report whose CPU lists all come after the ANR.
const _noCpuList = 'test/fixtures/back_anr_44445470776.txt';

String _samples(String state, int ticks, String wchan, String syscall) {
  String one(double uptime, int t) =>
      '--- sample\n$uptime 50.00\n'
      '24986 (bangwu.taildeck) $state 337 337 0 0 -1 4194624 1 0 0 0 $t 20 0 0\n'
      '$wchan\n$syscall 0x1 0x2\n';
  return '${one(100, 150)}${one(105, 150 + ticks)}--- anr\n';
}

String _trace(String frame) =>
    '----- pid 24986 at x -----\nCmd line: top.bangwu.taildeck\n\n'
    '"main" prio=5 tid=1 Native\n  native: #00 pc 1 libc.so (syscall+22)\n'
    '  $frame\n\n';

Future<(int, String)> _verdict(String samples, [String trace = '']) async {
  final dir = await Directory.systemTemp.createTemp('verdict');
  addTearDown(() => dir.delete(recursive: true));
  final s = File('${dir.path}/samples')..writeAsStringSync(samples);
  final t = File('${dir.path}/trace')..writeAsStringSync(trace);
  final run = await Process.start('python3', [
    'tool/compositor_stall.py',
    'top.bangwu.taildeck',
    s.path,
    t.path,
  ]);
  run.stdin.write(File(_noCpuList).readAsStringSync());
  await run.stdin.close();
  final text = await run.stdout
      .transform(const SystemEncoding().decoder)
      .join();
  return (await run.exitCode, text);
}

const _fakeAdb = r'''#!/usr/bin/env bash
case "$*" in
  "logcat -d"*) cat "$FAKE_LOGCAT" ;;
  "shell cmd package resolve-activity"*)
    echo top.bangwu.taildeck/top.bangwu.taildeck_ui.MainActivity ;;
  *"am start -W"*)
    printf 'Status: ok\nLaunchState: COLD\nActivity: top.bangwu.taildeck/top.bangwu.taildeck_ui.MainActivity\nTotalTime: 4859\n' ;;
  "shell pidof"*) exit 1 ;;
esac
exit 0
''';

Future<String> _runGate(String logcat) async {
  final dir = await Directory.systemTemp.createTemp('back-gate');
  addTearDown(() => dir.delete(recursive: true));
  for (final (name, body) in [
    ('adb', _fakeAdb),
    ('sleep', '#!/bin/sh\nexit 0\n'),
  ]) {
    final file = File('${dir.path}/$name')..writeAsStringSync(body);
    await Process.run('chmod', ['+x', file.path]);
  }
  final log = File('${dir.path}/logcat.txt')..writeAsStringSync(logcat);
  final out = '${dir.path}/out';
  await Process.run(
    'bash',
    ['tool/back_android.sh', 'app.apk', 'top.bangwu.taildeck', out],
    environment: {
      'PATH': '${dir.path}:${Platform.environment['PATH']}',
      'FAKE_LOGCAT': log.path,
      'GATE_FOCUS_WINDOW': '0',
    },
  );
  return File('$out/summary.txt').readAsStringSync();
}

void main() {
  final logcat = File(_fixture).readAsStringSync();

  test('an ANR met by the shell wait still gets the stall verdict', () async {
    final summary = await _runGate(logcat);
    expect(
      'compositor stall: com.android.systemui'.allMatches(summary).length,
      3,
    );
    expect(summary, contains('a third time: both ANRs were compositor stalls'));
    expect(summary, contains('emulator compositor stall on 3 cold starts'));
    expect(summary, isNot(contains('the shell did not settle')));
  });

  test('without another frozen process the ANR is the app\'s', () async {
    final appOnly = logcat
        .split('\n')
        .where((line) => !RegExp(r'^\S+ \S+\s+838 ').hasMatch(line))
        .join('\n');
    final summary = await _runGate(appOnly);
    expect('app-only ANR'.allMatches(summary).length, 2);
    expect(summary, contains('stopped answering input on 2 cold starts'));
  });

  group('an ANR report without a CPU list judges the main thread', () {
    test('blocked in binder at low CPU: compositor stall', () async {
      final (code, text) = await _verdict(
        _samples('S', 10, 'binder_ioctl_write_read', '16'),
      );
      expect(code, 0, reason: text);
      expect(text, contains('com.android.systemui (pid 838) froze 4833 ms'));
      expect(text, contains('main thread 2% CPU over 5.0 s'));
      expect(text, contains('wchan binder_ioctl_write_read'));
    });

    test('busy main thread: app-only', () async {
      final (code, text) = await _verdict(_samples('S', 250, 'ep_poll', '281'));
      expect(code, 1);
      expect(text, contains('busy'));
    });

    test('waiting on a file: app-only', () async {
      final (code, text) = await _verdict(
        _samples('D', 5, 'folio_wait_bit_common', '0'),
      );
      expect(code, 1);
      expect(text, contains('waiting on a file'));
    });

    test('futex under hwui: stall; futex on our own lock: app-only', () async {
      final futex = _samples('S', 5, 'futex_wait_queue', '202');
      final (hwui, _) = await _verdict(
        futex,
        _trace('native: #01 pc 2 libhwui.so (DrawFrameTask::postAndWait()+1)'),
      );
      expect(hwui, 0);
      final (lock, text) = await _verdict(
        futex,
        _trace('at java.lang.Object.wait(Native method)'),
      );
      expect(lock, 1);
      expect(text, contains('futex wait outside hwui/EGL/binder'));
    });

    test('no samples (app gone): app-only', () async {
      final (code, text) = await _verdict('');
      expect(code, 1);
      expect(text, contains('main thread unreadable'));
    });
  });
}
