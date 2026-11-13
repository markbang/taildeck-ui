import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'bridge.dart';

NativeBridge? openBridgePlatform() {
  final override = Platform.environment['TAILDECK_BRIDGE'];
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    if (Platform.isLinux)
      '${File(Platform.resolvedExecutable).parent.path}/lib/libtaildeck_bridge.so',
    if (Platform.isAndroid) 'libtaildeck_bridge.so',
  ];
  for (final path in candidates) {
    if (path.contains('/') && !File(path).existsSync()) continue;
    try {
      return FfiBridge(DynamicLibrary.open(path));
    } on Object {
      continue;
    }
  }
  return null;
}

typedef _StrFnNative = Pointer<Int8> Function();
typedef _StrFn = Pointer<Int8> Function();
typedef _StrArgNative = Pointer<Int8> Function(Pointer<Int8>);
typedef _StrArg = Pointer<Int8> Function(Pointer<Int8>);
typedef _IntFnNative = Int32 Function();
typedef _IntFn = int Function();
typedef _EventFn = Void Function(Int32, Pointer<Int8>, IntPtr);
typedef _FreeNative = Void Function(Pointer<Int8>);
typedef _Free = void Function(Pointer<Int8>);
typedef _SetCbNative = Void Function(Pointer<NativeFunction<_EventFn>>, IntPtr);
typedef _SetCb = void Function(Pointer<NativeFunction<_EventFn>>, int);

class FfiBridge implements NativeBridge {
  FfiBridge(DynamicLibrary lib)
    : _start = lib.lookupFunction<_StrArgNative, _StrArg>('td_start'),
      _stop = lib.lookupFunction<_StrFnNative, _StrFn>('td_stop'),
      _logout = lib.lookupFunction<_StrFnNative, _StrFn>('td_logout'),
      _networkChanged = lib
          .lookupFunction<_StrFnNative, _StrFn>('td_network_changed'),
      _status = lib.lookupFunction<_StrFnNative, _StrFn>('td_status'),
      _logs = lib.lookupFunction<_StrFnNative, _StrFn>('td_logs'),
      _ping = lib.lookupFunction<_StrArgNative, _StrArg>('td_ping'),
      _gatewayPort = lib.lookupFunction<_IntFnNative, _IntFn>(
        'td_gateway_port',
      ),
      _setEventCb = lib.lookupFunction<_SetCbNative, _SetCb>(
        'td_set_event_cb',
      ),
      _free = lib.lookupFunction<_FreeNative, _Free>('td_free') {
    _callback = NativeCallable<_EventFn>.listener(_onEvent);
    _setEventCb(_callback.nativeFunction, 0);
  }

  final _StrArg _start;
  final _StrFn _stop;
  final _StrFn _logout;
  final _StrFn _networkChanged;
  final _StrFn _status;
  final _StrFn _logs;
  final _StrArg _ping;
  final _IntFn _gatewayPort;
  final _SetCb _setEventCb;
  final _Free _free;
  late final NativeCallable<_EventFn> _callback;
  late final StreamController<BridgeEvent> _events =
      StreamController<BridgeEvent>.broadcast();

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Map<String, dynamic> start({
    required String dir,
    String hostname = 'taildeck',
    String controlURL = '',
    String authKey = '',
    int gatewayPort = 0,
    String platform = 'go',
  }) {
    return _callArg(
      _start,
      jsonEncode({
        'dir': dir,
        'hostname': hostname,
        'controlURL': controlURL,
        'authKey': authKey,
        'gatewayPort': gatewayPort,
        'platform': platform,
      }),
    );
  }

  @override
  void stop() => _call(_stop);

  @override
  void logout() => _call(_logout);

  @override
  void networkChanged() => _call(_networkChanged);

  @override
  Map<String, dynamic> status() => _call(_status);

  @override
  String logs() => _call(_logs)['logs'] as String? ?? '';

  @override
  int gatewayPort() => _gatewayPort();

  @override
  Map<String, dynamic> ping(String ip) => _callArg(_ping, ip);

  @override
  void dispose() {
    _setEventCb(nullptr, 0);
    _callback.close();
    _events.close();
  }

  /// The callback runs on Go threads; `NativeCallable.listener` posts it to
  /// this isolate, so the string is still valid here. Copy, then free.
  void _onEvent(int kind, Pointer<Int8> json, int ctx) {
    final text = json.cast<Utf8>().toDartString();
    _free(json);
    final BridgeEventKind? eventKind = switch (kind) {
      1 => BridgeEventKind.state,
      2 => BridgeEventKind.login,
      3 => BridgeEventKind.log,
      _ => null,
    };
    if (eventKind == null || text.isEmpty) return;
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    _events.add(BridgeEvent(eventKind, decoded));
  }

  Map<String, dynamic> _call(_StrFn fn) {
    final pointer = fn();
    if (pointer.address == 0) throw const BridgeException('bridge returned null');
    final text = pointer.cast<Utf8>().toDartString();
    _free(pointer);
    return _decode(text);
  }

  Map<String, dynamic> _callArg(_StrArg fn, String arg) {
    final input = arg.toNativeUtf8(allocator: calloc).cast<Int8>();
    try {
      return _call(() => fn(input));
    } finally {
      calloc.free(input);
    }
  }

  Map<String, dynamic> _decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw BridgeException('unexpected bridge reply: $text');
    }
    if (decoded['ok'] != true) {
      throw BridgeException(decoded['error'] as String? ?? text);
    }
    return decoded;
  }
}
