// Loads linux/lib/libtaildeck_bridge.so (tool/build_native.sh) and exercises the C ABI.
// No network: it only proves the exported symbols, JSON envelopes and
// string ownership (every char* is freed with td_free).
//
//   dart run tool/ffi_smoke.dart [path/to/libtaildeck_bridge.so]
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _StrFn = Pointer<Int8> Function();
typedef _StrArgFn = Pointer<Int8> Function(Pointer<Int8>);
typedef _IntFn = Int32 Function();
typedef _FreeFn = Void Function(Pointer<Int8>);
typedef _EventFn = Void Function(Int32, Pointer<Int8>, IntPtr);
typedef _SetCbFn = Void Function(Pointer<NativeFunction<_EventFn>>, IntPtr);
typedef _WriteFnNative = Pointer<Int8> Function(Int32, Pointer<Uint8>, Int32);
typedef _WriteFn = Pointer<Int8> Function(int, Pointer<Uint8>, int);
typedef _IntArgFnNative = Pointer<Int8> Function(Int32);
typedef _IntArgFn = Pointer<Int8> Function(int);
typedef _ResizeFnNative = Pointer<Int8> Function(Int32, Int32, Int32);
typedef _ResizeFn = Pointer<Int8> Function(int, int, int);
typedef _TwoStrFnNative = Pointer<Int8> Function(Pointer<Int8>, Pointer<Int8>);
typedef _TwoStrFn = Pointer<Int8> Function(Pointer<Int8>, Pointer<Int8>);

final _libc = DynamicLibrary.process();
final _calloc = _libc
    .lookupFunction<Pointer<Void> Function(IntPtr, IntPtr), Pointer<Void> Function(int, int)>(
      'calloc',
    );
final _free = _libc.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
  'free',
);

var _failures = 0;

void check(bool ok, String what) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'}  $what');
  if (!ok) _failures++;
}

Pointer<Int8> cstr(String s) {
  final bytes = utf8.encode(s);
  final p = _calloc(bytes.length + 1, 1).cast<Int8>();
  final view = p.cast<Uint8>();
  for (var i = 0; i < bytes.length; i++) {
    view[i] = bytes[i];
  }
  return p;
}

String readC(Pointer<Int8> p) {
  final view = p.cast<Uint8>();
  final bytes = <int>[];
  for (var i = 0; view[i] != 0; i++) {
    bytes.add(view[i]);
  }
  return utf8.decode(bytes);
}

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : 'linux/lib/libtaildeck_bridge.so';
  final lib = DynamicLibrary.open(path);

  final status = lib.lookupFunction<_StrFn, _StrFn>('td_status');
  final logs = lib.lookupFunction<_StrFn, _StrFn>('td_logs');
  final stop = lib.lookupFunction<_StrFn, _StrFn>('td_stop');
  final start = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_start');
  final free = lib.lookupFunction<_FreeFn, void Function(Pointer<Int8>)>('td_free');
  final port = lib.lookupFunction<_IntFn, int Function()>('td_gateway_port');
  final setCb = lib.lookupFunction<_SetCbFn, void Function(Pointer<NativeFunction<_EventFn>>, int)>(
    'td_set_event_cb',
  );
  final ping = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_ping');
  final probe = lib.lookupFunction<_TwoStrFnNative, _TwoStrFn>('td_probe');
  final sshDial = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_ssh_dial');
  final sshWrite = lib.lookupFunction<_WriteFnNative, _WriteFn>('td_ssh_write');
  final sshResize = lib.lookupFunction<_ResizeFnNative, _ResizeFn>('td_ssh_resize');
  final sshClose = lib.lookupFunction<_IntArgFnNative, _IntArgFn>('td_ssh_close');
  final keyEnsure = lib.lookupFunction<_TwoStrFnNative, _TwoStrFn>('td_key_ensure');
  final forgetHostKeys = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_forget_host_keys');
  final herdrConnect = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_herdr_connect');
  final herdrCall = lib.lookupFunction<_TwoStrFnNative, _TwoStrFn>('td_herdr_call');
  final herdrClose = lib.lookupFunction<_StrFn, _StrFn>('td_herdr_close');

  String call(Pointer<Int8> Function() fn) {
    final p = fn();
    if (p.address == 0) return '<null>';
    final s = readC(p);
    free(p);
    return s;
  }

  String callArg(Pointer<Int8> Function(Pointer<Int8>) fn, String arg) {
    final a = cstr(arg);
    try {
      return call(() => fn(a));
    } finally {
      _free(a.cast());
    }
  }

  String callTwo(Pointer<Int8> Function(Pointer<Int8>, Pointer<Int8>) fn, String a, String b) {
    final pa = cstr(a);
    final pb = cstr(b);
    try {
      return call(() => fn(pa, pb));
    } finally {
      _free(pa.cast());
      _free(pb.cast());
    }
  }

  Map<String, dynamic> decode(String text) => jsonDecode(text) as Map<String, dynamic>;

  // Events arrive on Go threads, so the listener posts them to this isolate;
  // the payload stays valid until we free it, which is why Go hands it over.
  final events = <Map<String, dynamic>>[];
  final cb = NativeCallable<_EventFn>.listener((int kind, Pointer<Int8> json, int ctx) {
    final text = readC(json);
    free(json);
    events.add({'kind': kind, ...jsonDecode(text) as Map<String, dynamic>});
  });
  setCb(cb.nativeFunction, 0);

  final out = <String>[];
  out.add('status before start: ${call(status)}');
  out.add('logs: ${call(logs)}');
  out.add('gateway port: ${port()}');
  out.add('stop when stopped: ${call(stop)}');
  out.add('start without dir: ${callArg(start, '{"hostname":"smoke"}')}');
  out.add(
    'start with bad platform: ${callArg(start, '{"dir":"/tmp/td-smoke","platform":"bogus"}')}',
  );
  out.add(
    'start with host platform, no hooks: ${callArg(start, '{"dir":"/tmp/td-smoke","platform":"host"}')}',
  );
  out.add('ping without engine: ${callArg(ping, '100.64.0.1')}');
  out.add('probe without engine: ${callTwo(probe, '100.64.0.1', '80,443')}');

  // Probing before start has no node to dial through: a clean envelope.
  // herdr before the node exists: a clean envelope, never a crash or a hang.
  final beforeHerdr = decode(
    callArg(herdrConnect, '{"host":"devbox","user":"root"}'),
  );
  check(beforeHerdr['ok'] == false, 'td_herdr_connect without a node fails');
  check(
    (beforeHerdr['error'] as String? ?? '').contains('not running'),
    'td_herdr_connect error names the missing node: ${beforeHerdr['error']}',
  );
  check(
    decode(callArg(herdrConnect, ''))['ok'] == false,
    'td_herdr_connect without a config fails',
  );
  check(
    decode(callArg(herdrConnect, '{"user":"root"}'))['ok'] == false,
    'td_herdr_connect without a host fails',
  );
  final noHerdrCall = decode(callTwo(herdrCall, 'agent.list', '{}'));
  check(noHerdrCall['ok'] == false, 'td_herdr_call without a connection fails');
  check(
    (noHerdrCall['error'] as String? ?? '').contains('not connected'),
    'td_herdr_call explains the missing connection: ${noHerdrCall['error']}',
  );
  check(
    decode(call(herdrClose))['ok'] == true,
    'td_herdr_close without a connection is a no-op',
  );

  final beforeProbe = decode(callTwo(probe, '100.64.0.1', '80,443'));
  check(beforeProbe['ok'] == false, 'td_probe without a node fails');
  check(
    (beforeProbe['error'] as String? ?? '').contains('not started'),
    'td_probe error names the missing node: ${beforeProbe['error']}',
  );

  // SSH before the node exists: a clean envelope, never a crash or a hang.
  final beforeSSH = decode(callArg(sshDial, '{"host":"100.64.0.1","user":"root"}'));
  check(beforeSSH['ok'] == false, 'ssh_dial without a node fails');
  check(
    (beforeSSH['error'] as String? ?? '').contains('not running'),
    'ssh_dial error names the missing node: ${beforeSSH['error']}',
  );
  out.add('ssh_dial empty config: ${callArg(sshDial, '')}');
  out.add('ssh_dial without host: ${callArg(sshDial, '{"user":"root"}')}');
  check(
    decode(callArg(sshDial, '{"host":"x","port":70000}'))['ok'] == false,
    'ssh_dial rejects a bad port',
  );
  final unknownWrite = decode(
    (() {
      final p = _calloc(1, 1).cast<Uint8>();
      try {
        return call(() => sshWrite(99, p, 0));
      } finally {
        _free(p.cast());
      }
    })(),
  );
  check(unknownWrite['ok'] == false, 'ssh_write on an unknown id fails: ${unknownWrite['error']}');
  check(
    decode(call(() => sshResize(99, 80, 24)))['ok'] == false,
    'ssh_resize on an unknown id fails',
  );
  check(decode(call(() => sshClose(99)))['ok'] == true, 'ssh_close on an unknown id is a no-op');

  // Built-in key: created once, reused, and the public half is returned.
  final keyDir = Directory.systemTemp.createTempSync('td-key');
  final keyPath = '${keyDir.path}/ssh/id_ed25519';
  final key1 = decode(callTwo(keyEnsure, keyPath, 'taildeck@smoke'));
  check(key1['ok'] == true, 'td_key_ensure creates a key: ${key1['error'] ?? ''}');
  check(
    (key1['public'] as String? ?? '').startsWith('ssh-ed25519 '),
    'key has an ed25519 public line',
  );
  check(File(keyPath).existsSync(), 'key file exists on disk');
  final key2 = decode(callTwo(keyEnsure, keyPath, 'taildeck@smoke'));
  check(key2['public'] == key1['public'], 'td_key_ensure reuses the existing key');
  check(decode(callTwo(keyEnsure, '', ''))['ok'] == false, 'td_key_ensure without a path fails');
  check(
    decode(callArg(forgetHostKeys, keyDir.path))['ok'] == true,
    'td_forget_host_keys on an empty dir is ok',
  );
  keyDir.deleteSync(recursive: true);

  // Local start against a refused control URL: no tailnet traffic, but the
  // node, gateway port and state events run for real.
  final dir = Directory.systemTemp.createTempSync('td-smoke');
  final started = callArg(
    start,
    jsonEncode({'dir': dir.path, 'hostname': 'td-smoke', 'controlURL': 'http://127.0.0.1:1'}),
  );
  out.add('start: $started');
  out.add('gateway port after start: ${port()}');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  out.add('events: ${events.length}');
  out.add('first event: ${events.isEmpty ? '-' : jsonEncode(events.first)}');
  out.add('event kinds: ${events.map((e) => e['kind']).toSet().toList()..sort()}');
  final st = jsonDecode(call(status)) as Map<String, dynamic>;
  out.add('status state: ${st['state']} (ok=${st['ok']})');

  // The node is up but not signed in: SSH must say so instead of dialing.
  final before = DateTime.now();
  final unready = decode(callArg(sshDial, '{"host":"devbox","user":"root"}'));
  final elapsed = DateTime.now().difference(before).inMilliseconds;
  final unreadyError = unready['error'] as String? ?? '';
  check(unready['ok'] == false, 'ssh_dial with an unauthenticated node fails in ${elapsed}ms');
  check(
    unreadyError.contains('not logged in') || unreadyError.contains('not running'),
    'ssh_dial explains the state: $unreadyError',
  );
  check(!events.any((e) => e['kind'] == 4 || e['kind'] == 5), 'no SSH session events were emitted');

  // The node is up but not signed in: herdr must say so instead of dialing.
  final herdrUnready = decode(
    callArg(herdrConnect, '{"host":"devbox","user":"root"}'),
  );
  check(
    herdrUnready['ok'] == false,
    'td_herdr_connect with an unauthenticated node fails',
  );
  check(
    (herdrUnready['error'] as String? ?? '').contains('not logged in'),
    'td_herdr_connect explains the state: ${herdrUnready['error']}',
  );
  check(
    !events.any((e) => e['kind'] == 6),
    'no herdr events without a connection',
  );

  out.add('stop: ${call(stop)}');

  cb.close();
  dir.deleteSync(recursive: true);
  stdout.writeln(out.join('\n'));
  if (_failures > 0) {
    stdout.writeln('$_failures check(s) failed');
    exitCode = 1;
  }
}
