/// The Go tsnet bridge (`native/bridge/cmd/cshared`) through dart:ffi.
///
/// Every function returns JSON; `{"ok":false,"error":"..."}` becomes a
/// [BridgeException]. The event callback owns its strings: the FFI layer copies
/// the payload and calls `td_free`.
library;

import 'dart:typed_data';

import 'bridge_stub.dart' if (dart.library.ffi) 'bridge_impl.dart';

enum BridgeEventKind { state, login, log, sshData, sshClosed }

class BridgeEvent {
  const BridgeEvent(this.kind, this.data);

  final BridgeEventKind kind;
  final Map<String, dynamic> data;

  /// Backend state name (`NeedsLogin`, `Starting`, `Running`, ...).
  String get state => data['state'] as String? ?? '';

  /// Login URL the user must open in a browser.
  String get url => data['url'] as String? ?? '';

  String get line => data['line'] as String? ?? '';

  /// SSH session this event belongs to (kinds `sshData` / `sshClosed`).
  int get id => (data['id'] as num?)?.toInt() ?? 0;

  /// Base64 output payload of an `sshData` event.
  String get output => data['data'] as String? ?? '';

  /// Why an `sshClosed` session ended.
  String get reason => data['reason'] as String? ?? '';
}

/// One frame of an SSH session: output bytes, or the end with a reason.
class SshOutput {
  const SshOutput.data(this.bytes, {this.notice = false}) : reason = '';

  const SshOutput.closed(this.reason) : bytes = null, notice = false;

  final Uint8List? bytes;
  final String reason;

  /// A local notice (such as "connecting"), not remote output.
  final bool notice;

  bool get closed => bytes == null;
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

  /// Ports from the comma-separated [ports] that accept a TCP connection on
  /// [host], dialed through the tailnet node.
  List<int> probe(String host, String ports);
  void dispose();

  /// Opens an interactive PTY shell over the tailnet and returns its id.
  /// Dialing continues in the background: output and close come as
  /// [sshOutput] frames.
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
  });

  void sshWrite(int id, Uint8List data);
  void sshResize(int id, int cols, int rows);
  void sshClose(int id);

  /// Output of session [id]. Buffers frames emitted before the first listen.
  Stream<SshOutput> sshOutput(int id);

  /// Creates the ed25519 key at [path] when missing; returns its public line.
  String ensureKey(String path, {String comment = 'taildeck'});

  /// Drops the trusted host keys stored in [dir].
  void forgetHostKeys(String dir);
}

/// Null on web or when the shared library is missing; callers fall back to
/// mock data.
NativeBridge? openNativeBridge() => openBridgePlatform();
