@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Run 44438129087: the focus ANR killed the app while wait_home was still
// waiting, and the gate failed with "the shell did not settle" and no verdict.
const _fixture = 'test/fixtures/back_anr_44438129087.txt';

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
}
