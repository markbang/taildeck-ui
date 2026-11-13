/// The Go tsnet bridge (`native/bridge/cmd/cshared`) through dart:ffi.
///
/// Every function returns JSON; `{"ok":false,"error":"..."}` becomes a
/// [BridgeException]. The event callback owns its strings: the FFI layer copies
/// the payload and calls `td_free`.
library;

import 'bridge_stub.dart' if (dart.library.ffi) 'bridge_impl.dart';

enum BridgeEventKind { state, login, log }

class BridgeEvent {
  const BridgeEvent(this.kind, this.data);

  final BridgeEventKind kind;
  final Map<String, dynamic> data;

  /// Backend state name (`NeedsLogin`, `Starting`, `Running`, ...).
  String get state => data['state'] as String? ?? '';

  /// Login URL the user must open in a browser.
  String get url => data['url'] as String? ?? '';

  String get line => data['line'] as String? ?? '';
}

class BridgeException implements Exception {
  const BridgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class NativeBridge {
  /// State / login / log events, delivered on the root isolate.
  Stream<BridgeEvent> get events;

  Map<String, dynamic> start({
    required String dir,
    String hostname = 'taildeck',
    String controlURL = '',
    String authKey = '',
    int gatewayPort = 0,
    String platform = 'go',
  });

  void stop();
  void logout();
  void networkChanged();
  Map<String, dynamic> status();
  String logs();
  int gatewayPort();
  Map<String, dynamic> ping(String ip);
  void dispose();
}

/// Null on web or when the shared library is missing; callers fall back to
/// mock data.
NativeBridge? openNativeBridge() => openBridgePlatform();
