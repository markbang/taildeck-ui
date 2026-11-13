import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bridge.dart';

NativeBridge? openBridgePlatform() {
  final override = Platform.environment['TAILDECK_BRIDGE'];
  final candidates = <String>[
    if (override != null && override.isNotEmpty) override,
    if (Platform.isLinux)
      '${File(Platform.resolvedExecutable).parent.path}/lib/libtaildeck_bridge.so',
    if (Platform.isAndroid) 'libtaildeck_bridge.so',
    if (Platform.isWindows) 'taildeck_bridge.dll',
    if (Platform.isMacOS)
      '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/libtaildeck_bridge.dylib',
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
typedef _IntArgNative = Pointer<Int8> Function(Int32);
typedef _IntArg = Pointer<Int8> Function(int);
typedef _WriteNative = Pointer<Int8> Function(Int32, Pointer<Uint8>, Int32);
typedef _Write = Pointer<Int8> Function(int, Pointer<Uint8>, int);
typedef _ResizeNative = Pointer<Int8> Function(Int32, Int32, Int32);
typedef _Resize = Pointer<Int8> Function(int, int, int);
typedef _TwoStrNative = Pointer<Int8> Function(Pointer<Int8>, Pointer<Int8>);
typedef _TwoStr = Pointer<Int8> Function(Pointer<Int8>, Pointer<Int8>);

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
      _probe = lib.lookupFunction<_TwoStrNative, _TwoStr>('td_probe'),
      _gatewayPort = lib.lookupFunction<_IntFnNative, _IntFn>(
        'td_gateway_port',
      ),
      _setEventCb = lib.lookupFunction<_SetCbNative, _SetCb>(
        'td_set_event_cb',
      ),
      _sshDial = lib.lookupFunction<_StrArgNative, _StrArg>('td_ssh_dial'),
      _sshWrite = lib.lookupFunction<_WriteNative, _Write>('td_ssh_write'),
      _sshResize = lib.lookupFunction<_ResizeNative, _Resize>('td_ssh_resize'),
      _sshClose = lib.lookupFunction<_IntArgNative, _IntArg>('td_ssh_close'),
      _keyEnsure = lib.lookupFunction<_TwoStrNative, _TwoStr>('td_key_ensure'),
      _forgetHostKeys = lib.lookupFunction<_StrArgNative, _StrArg>(
        'td_forget_host_keys',
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
  final _TwoStr _probe;
  final _IntFn _gatewayPort;
  final _SetCb _setEventCb;
  final _StrArg _sshDial;
  final _Write _sshWrite;
  final _Resize _sshResize;
  final _IntArg _sshClose;
  final _TwoStr _keyEnsure;
  final _StrArg _forgetHostKeys;
  final _Free _free;
  late final NativeCallable<_EventFn> _callback;
  late final StreamController<BridgeEvent> _events =
      StreamController<BridgeEvent>.broadcast();
  final Map<int, StreamController<SshOutput>> _ssh = {};

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
  List<int> probe(String host, String ports) {
    final reply = _callTwo(_probe, host, ports);
    return [
      for (final port in reply['ports'] as List? ?? const [])
        if (port is num) port.toInt(),
    ];
  }

  @override
  Map<String, dynamic> sshDial({
    required String host,
    int port = 22,
    String user = 'root',
    String password = '',
    String keyPath = '',
    String passphrase = '',
    String certPath = '',
    int cols = 80,
    int rows = 24,
  }) {
    final reply = _callArg(
      _sshDial,
      jsonEncode({
        'host': host,
        'port': port,
        'user': user,
        'password': password,
        'keyPath': keyPath,
        'passphrase': passphrase,
        'certPath': certPath,
        'cols': cols,
        'rows': rows,
      }),
    );
    final id = (reply['id'] as num?)?.toInt();
    if (id == null) throw const BridgeException('ssh_dial returned no id');
    // Created before returning: the callback cannot run during this call, so
    // no output frame of this session can arrive before the controller exists.
    _ssh[id] = StreamController<SshOutput>();
    return reply;
  }

  @override
  void sshWrite(int id, Uint8List data) {
    if (data.isEmpty) return;
    final buffer = calloc<Uint8>(data.length);
    try {
      buffer.asTypedList(data.length).setAll(0, data);
      _call(() => _sshWrite(id, buffer, data.length));
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  void sshResize(int id, int cols, int rows) =>
      _call(() => _sshResize(id, cols, rows));

  @override
  void sshClose(int id) {
    _call(() => _sshClose(id));
    _closeOutput(id, null);
  }

  @override
  Stream<SshOutput> sshOutput(int id) =>
      _ssh[id]?.stream ?? const Stream<SshOutput>.empty();

  @override
  String ensureKey(String path, {String comment = 'taildeck'}) {
    final reply = _callTwo(_keyEnsure, path, comment);
    final pub = reply['public'] as String? ?? '';
    if (pub.isEmpty) throw const BridgeException('key has no public part');
    return pub;
  }

  @override
  void forgetHostKeys(String dir) => _callArg(_forgetHostKeys, dir);

  @override
  void dispose() {
    for (final controller in _ssh.values) {
      if (!controller.isClosed) controller.close();
    }
    _ssh.clear();
    _setEventCb(nullptr, 0);
    _callback.close();
    _events.close();
  }

  void _closeOutput(int id, String? reason) {
    final controller = _ssh.remove(id);
    if (controller == null || controller.isClosed) return;
    if (reason != null) controller.add(SshOutput.closed(reason));
    controller.close();
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
      4 => BridgeEventKind.sshData,
      5 => BridgeEventKind.sshClosed,
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
    final event = BridgeEvent(eventKind, decoded);
    if (eventKind == BridgeEventKind.sshData ||
        eventKind == BridgeEventKind.sshClosed) {
      _onSshEvent(event);
      return;
    }
    _events.add(event);
  }

  /// SSH frames go to their session stream only: they carry terminal bytes and
  /// would otherwise wake every listener of [events].
  void _onSshEvent(BridgeEvent event) {
    final controller = _ssh[event.id];
    if (controller == null || controller.isClosed) return;
    if (event.kind == BridgeEventKind.sshClosed) {
      controller.add(SshOutput.closed(event.reason));
      _closeOutput(event.id, null);
      return;
    }
    if (event.output.isEmpty) return;
    try {
      controller.add(
        SshOutput.data(
          base64Decode(event.output),
          notice: event.data['notice'] == true,
        ),
      );
    } on FormatException {
      return;
    }
  }

  Map<String, dynamic> _call(_StrFn fn) {
    final pointer = fn();
    if (pointer.address == 0) throw const BridgeException('bridge returned null');
    final text = pointer.cast<Utf8>().toDartString();
    _free(pointer);
    return _decode(text);
  }

  Map<String, dynamic> _callTwo(_TwoStr fn, String first, String second) {
    final a = first.toNativeUtf8(allocator: calloc).cast<Int8>();
    final b = second.toNativeUtf8(allocator: calloc).cast<Int8>();
    try {
      return _call(() => fn(a, b));
    } finally {
      calloc.free(a);
      calloc.free(b);
    }
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
