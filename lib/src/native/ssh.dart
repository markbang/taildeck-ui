import 'dart:typed_data';

import 'bridge.dart';

/// One SSH session owned by the Go node: output frames, input and resize.
///
/// Writes are dropped once the session is closed; the [output] stream carries
/// the close frame, which is what the UI reacts to.
class SshSession {
  SshSession(this.bridge, this.id);

  final NativeBridge bridge;
  final int id;

  /// Output of this session; buffers frames emitted before the first listen.
  late final Stream<SshOutput> output = bridge.sshOutput(id);

  bool _closed = false;
  bool get closed => _closed;

  void write(Uint8List data) {
    if (_closed || data.isEmpty) return;
    try {
      bridge.sshWrite(id, data);
    } on BridgeException {
      // Not connected yet or already gone: the close frame reports the rest.
    }
  }

  void resize(int cols, int rows) {
    if (_closed) return;
    try {
      bridge.sshResize(id, cols, rows);
    } on BridgeException {
      // Same as write: a closed session ignores late resizes.
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      bridge.sshClose(id);
    } on BridgeException {
      // Nothing left to close.
    }
  }
}
