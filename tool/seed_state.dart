// Registers a tailnet node against a test control plane and leaves its tsnet
// state dir behind, so an emulator gate can start the app signed in without
// driving the login page (a tap there can fall back to the browser flow).
//
//   dart run tool/seed_state.dart <lib.so> <dir> <control-url> <auth-key> [hostname]
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _StrFn = Pointer<Int8> Function();
typedef _StrArgFn = Pointer<Int8> Function(Pointer<Int8>);
typedef _FreeFn = Void Function(Pointer<Int8>);

final _libc = DynamicLibrary.process();
final _calloc = _libc
    .lookupFunction<
      Pointer<Void> Function(IntPtr, IntPtr),
      Pointer<Void> Function(int, int)
    >('calloc');
final _free = _libc
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'free',
    );

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
  if (args.length < 4) {
    stderr.writeln(
      'usage: seed_state.dart <lib.so> <dir> <control-url> <auth-key> [hostname]',
    );
    exit(2);
  }
  final lib = DynamicLibrary.open(args[0]);
  final dir = args[1];
  final control = args[2];
  final key = args[3];
  final hostname = args.length > 4 ? args[4] : 'taildeck';
  Directory(dir).createSync(recursive: true);

  final start = lib.lookupFunction<_StrArgFn, _StrArgFn>('td_start');
  final status = lib.lookupFunction<_StrFn, _StrFn>('td_status');
  final stop = lib.lookupFunction<_StrFn, _StrFn>('td_stop');
  final free = lib.lookupFunction<_FreeFn, void Function(Pointer<Int8>)>(
    'td_free',
  );

  String call(Pointer<Int8> Function() fn) {
    final p = fn();
    if (p.address == 0) return '{}';
    final text = readC(p);
    free(p);
    return text;
  }

  final config = cstr(
    jsonEncode({
      'dir': dir,
      'hostname': hostname,
      'controlURL': control,
      'authKey': key,
      'gatewayPort': 0,
      'platform': 'go',
    }),
  );
  final reply = call(() => start(config));
  _free(config.cast());
  if (!reply.contains('"ok":true')) {
    stderr.writeln('start failed: $reply');
    exit(1);
  }

  for (var i = 0; i < 200; i++) {
    final now = jsonDecode(call(status)) as Map<String, dynamic>;
    final self = now['self'];
    final ips = self is Map<String, dynamic> ? self['ips'] as List? : null;
    if (now['state'] == 'Running' &&
        now['netmap'] == true &&
        (ips?.isNotEmpty ?? false)) {
      call(stop);
      final state = File('$dir/tailscaled.state');
      if (!state.existsSync()) {
        stderr.writeln('no state file in $dir');
        exit(1);
      }
      stdout.writeln('seeded $hostname at $dir (${state.lengthSync()} bytes)');
      exit(0);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  call(stop);
  stderr.writeln('the node did not reach Running');
  exit(1);
}
