/// Flutter key events to `GhosttyKey` codes for `td_term_encode_key`.
///
/// The numbers mirror the `GhosttyKey` enum (ghostty/vt/key/event.h, pinned
/// rev 83b57ac); the C shim takes them as plain ints.
library;

import 'package:flutter/services.dart';

abstract final class GhosttyMods {
  static const shift = 1 << 0;
  static const ctrl = 1 << 1;
  static const alt = 1 << 2;
  static const superKey = 1 << 3;
}

const _keys = <int, int>{
  0x10000000d: 58, // enter
  0x20000020d: 58, // numpad enter
  0x100000008: 53, // backspace
  0x100000009: 64, // tab
  0x10000001b: 120, // escape
  0x10000007f: 68, // delete
  0x100000407: 72, // insert
  0x100000306: 71, // home
  0x100000305: 69, // end
  0x100000308: 74, // page up
  0x100000307: 73, // page down
  0x100000304: 78, // arrow up
  0x100000301: 75, // arrow down
  0x100000302: 76, // arrow left
  0x100000303: 77, // arrow right
  0x100000801: 121, // F1
  0x100000802: 122,
  0x100000803: 123,
  0x100000804: 124,
  0x100000805: 125,
  0x100000806: 126,
  0x100000807: 127,
  0x100000808: 128,
  0x100000809: 129,
  0x10000080a: 130,
  0x10000080b: 131,
  0x10000080c: 132, // F12
};

/// GhosttyKey for a printable string, or 0 when it has no key code.
int ghosttyKeyForText(String text) {
  if (text.isEmpty) return 0;
  final rune = text.runes.first;
  if (rune >= 0x41 && rune <= 0x5a) return 20 + rune - 0x41;
  if (rune >= 0x61 && rune <= 0x7a) return 20 + rune - 0x61;
  if (rune >= 0x30 && rune <= 0x39) return 6 + rune - 0x30;
  return switch (rune) {
    0x60 || 0x7e => 1, // ` ~
    0x5c || 0x7c => 2, // \ |
    0x5b || 0x7b => 3, // [ {
    0x5d || 0x7d => 4, // ] }
    0x2c || 0x3c => 5, // , <
    0x3d || 0x2b => 16, // = +
    0x2d || 0x5f => 46, // - _
    0x2e || 0x3e => 47, // . >
    0x27 || 0x22 => 48, // ' "
    0x3b || 0x3a => 49, // ; :
    0x2f || 0x3f => 50, // / ?
    0x20 => 63, // space
    _ => 0,
  };
}

int ghosttyModsOf(HardwareKeyboard keyboard) {
  var mods = 0;
  if (keyboard.isShiftPressed) mods |= GhosttyMods.shift;
  if (keyboard.isControlPressed) mods |= GhosttyMods.ctrl;
  if (keyboard.isAltPressed) mods |= GhosttyMods.alt;
  if (keyboard.isMetaPressed) mods |= GhosttyMods.superKey;
  return mods;
}

/// Key code for a hardware event. The layout label wins over the produced
/// character so Ctrl+[ and Ctrl+letter still name a key.
int ghosttyKeyOf(KeyEvent event) {
  final mapped = _keys[event.logicalKey.keyId];
  if (mapped != null) return mapped;
  final label = event.logicalKey.keyLabel;
  if (label.length == 1) return ghosttyKeyForText(label);
  final text = event.character;
  if (text != null && text.isNotEmpty) return ghosttyKeyForText(text);
  return 0;
}
