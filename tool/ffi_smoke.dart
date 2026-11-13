// Loads native/bridge/build/libtaildeck_bridge.so and exercises the C ABI.
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

final _libc = DynamicLibrary.process();
final _calloc = _libc.lookupFunction<Pointer<Void> Function(IntPtr, IntPtr), Pointer<Void> Function(int, int)>('calloc');
final _free = _libc.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');

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
  final path = args.isNotEmpty ? args.first : 'native/bridge/build/libtaildeck_bridge.so';
  final lib = DynamicLibrary.open(path);

  final status = lib.lookupFunction<_StrFn, _StrFn>('td_status');
  final logs = lib.lookupFunction<_StrFn, _StrFn>('td_logs');
  final stop = lib.lookupFunction<_StrFn, _StrFn>('td_stop');
  final start = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_start');
  final free = lib.lookupFunction<_FreeFn, void Function(Pointer<Int8>)>('td_free');
  final port = lib.lookupFunction<_IntFn, int Function()>('td_gateway_port');
  final setCb = lib.lookupFunction<_SetCbFn, void Function(Pointer<NativeFunction<_EventFn>>, int)>('td_set_event_cb');
  final ping = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_ping');

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
  out.add('start with bad platform: ${callArg(start, '{"dir":"/tmp/td-smoke","platform":"bogus"}')}');
  out.add('start with host platform, no hooks: ${callArg(start, '{"dir":"/tmp/td-smoke","platform":"host"}')}');
  out.add('ping without engine: ${callArg(ping, '100.64.0.1')}');
  // Local start against a refused control URL: no tailnet traffic, but the
  // node, gateway port and state events run for real.
  final dir = Directory.systemTemp.createTempSync('td-smoke');
  final started = callArg(start, jsonEncode({
    'dir': dir.path,
    'hostname': 'td-smoke',
    'controlURL': 'http://127.0.0.1:1',
  }));
  out.add('start: $started');
  out.add('gateway port after start: ${port()}');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  out.add('events: ${events.length}');
  out.add('first event: ${events.isEmpty ? '-' : jsonEncode(events.first)}');
  out.add('event kinds: ${events.map((e) => e['kind']).toSet().toList()..sort()}');
  final st = jsonDecode(call(status)) as Map<String, dynamic>;
  out.add('status state: ${st['state']} (ok=${st['ok']})');
  out.add('stop: ${call(stop)}');
  out.add('status after stop: ${call(status)}');

  cb.close();
  dir.deleteSync(recursive: true);
  stdout.writeln(out.join('\n'));
}
