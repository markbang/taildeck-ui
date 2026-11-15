/// The extra key row above the soft keyboard: the key catalog, which keys each
/// page shows, and how a tap becomes bytes through libghostty-vt.
library;

import 'dart:typed_data';

import 'native/keys.dart';
import 'native/term.dart';

/// A modifier the row holds for the next key.
enum TerminalMod { ctrl, alt }

enum TerminalKeyKind { modifier, key, character, toggle }

class TerminalKey {
  const TerminalKey(
    this.id,
    this.label, {
    this.code,
    this.text,
    this.modifier,
    this.toggle = false,
  });

  /// Stable id, persisted in the app config.
  final String id;

  /// Shown on the key; a key's own name rather than prose, so it reads the
  /// same in both languages.
  final String label;

  /// `GhosttyKey` code, for a named key.
  final int? code;

  /// The character to send, for a printable key.
  final String? text;

  final TerminalMod? modifier;

  /// A switch on the terminal rather than a byte: the page acts on its id.
  final bool toggle;

  TerminalKeyKind get kind => toggle
      ? TerminalKeyKind.toggle
      : modifier != null
      ? TerminalKeyKind.modifier
      : text != null
      ? TerminalKeyKind.character
      : TerminalKeyKind.key;
}

/// Every key the row can show. A key appears on one page at a time.
const terminalKeyCatalog = <TerminalKey>[
  TerminalKey('esc', 'Esc', code: GhosttyKeys.escape),
  TerminalKey('tab', 'Tab', code: GhosttyKeys.tab),
  TerminalKey('ctrl', 'Ctrl', modifier: TerminalMod.ctrl),
  TerminalKey('alt', 'Alt', modifier: TerminalMod.alt),
  TerminalKey('left', '←', code: GhosttyKeys.arrowLeft),
  TerminalKey('up', '↑', code: GhosttyKeys.arrowUp),
  TerminalKey('down', '↓', code: GhosttyKeys.arrowDown),
  TerminalKey('right', '→', code: GhosttyKeys.arrowRight),
  TerminalKey('home', 'Home', code: GhosttyKeys.home),
  TerminalKey('end', 'End', code: GhosttyKeys.end),
  TerminalKey('pgup', 'PgUp', code: GhosttyKeys.pageUp),
  TerminalKey('pgdn', 'PgDn', code: GhosttyKeys.pageDown),
  TerminalKey('pipe', '|', text: '|'),
  TerminalKey('tilde', '~', text: '~'),
  TerminalKey('slash', '/', text: '/'),
  TerminalKey('dash', '-', text: '-'),
  TerminalKey('underscore', '_', text: '_'),
  TerminalKey('colon', ':', text: ':'),
  TerminalKey('star', '*', text: '*'),
  TerminalKey('amp', '&', text: '&'),
  TerminalKey('equals', '=', text: '='),
  TerminalKey('question', '?', text: '?'),
  TerminalKey('quote', "'", text: "'"),
  TerminalKey('backslash', '\\', text: '\\'),
  TerminalKey('insert', 'Ins', toggle: true),
];

final _byId = {for (final key in terminalKeyCatalog) key.id: key};

TerminalKey? terminalKeyById(String id) => _byId[id];

/// A row page holds at most this many keys before the labels crowd.
const maxKeysPerPage = 9;

/// More pages than this and the dots stop being tappable targets.
const maxKeyPages = 3;

const defaultTerminalKeyPages = <List<String>>[
  ['esc', 'tab', 'ctrl', 'alt', 'left', 'up', 'down', 'right'],
  ['home', 'end', 'pgup', 'pgdn', 'pipe', 'tilde', 'slash', 'dash', 'insert'],
  [
    'underscore',
    'colon',
    'star',
    'amp',
    'equals',
    'question',
    'quote',
    'backslash',
  ],
];

/// Pages from stored JSON: unknown ids, duplicates and oversized pages are
/// dropped, and an empty page stays empty so the row can skip it. A missing
/// value (`null`) means the user never changed anything.
List<List<String>> parseTerminalKeyPages(Object? value) {
  if (value is! List) return defaultTerminalKeyPages;
  final seen = <String>{};
  final pages = <List<String>>[];
  for (final page in value) {
    if (page is! List) continue;
    final ids = <String>[];
    for (final id in page) {
      if (ids.length >= maxKeysPerPage) break;
      if (id is! String) continue;
      final key = _byId[id];
      if (key == null || !seen.add(id)) continue;
      ids.add(id);
    }
    pages.add(ids);
    if (pages.length >= maxKeyPages) break;
  }
  return pages;
}

/// Bytes [key] sends with [mods] armed; null when the emulator cannot encode it.
Uint8List? encodeTerminalKey(NativeTerm term, TerminalKey key, int mods) {
  if (key.toggle) return null;
  final text = key.text;
  if (text != null) {
    return term.encodeKey(ghosttyKeyForText(text), mods, text: text);
  }
  final code = key.code;
  return code == null ? null : term.encodeKey(code, mods);
}

/// Sticky Ctrl/Alt: one tap arms the modifier, a second tap inside
/// [doubleTap] locks it, and a tap on a locked modifier clears it.
class TerminalMods {
  static const doubleTap = Duration(milliseconds: 320);

  bool ctrlArmed = false;
  bool altArmed = false;
  bool ctrlLocked = false;
  bool altLocked = false;
  DateTime? _ctrlTapped;
  DateTime? _altTapped;

  int get mask =>
      (ctrlArmed || ctrlLocked ? GhosttyMods.ctrl : 0) |
      (altArmed || altLocked ? GhosttyMods.alt : 0);

  bool isArmed(TerminalMod mod) =>
      mod == TerminalMod.ctrl ? ctrlArmed : altArmed;

  bool isLocked(TerminalMod mod) =>
      mod == TerminalMod.ctrl ? ctrlLocked : altLocked;

  /// Applies one tap on [mod].
  void tap(TerminalMod mod, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = mod == TerminalMod.ctrl ? _ctrlTapped : _altTapped;
    final armed = isArmed(mod);
    final locked = isLocked(mod);
    final lock = armed && last != null && at.difference(last) < doubleTap;
    final nextArmed = !locked && !armed;
    final nextLocked = lock;
    if (mod == TerminalMod.ctrl) {
      ctrlArmed = nextArmed;
      ctrlLocked = nextLocked;
      _ctrlTapped = locked ? null : at;
    } else {
      altArmed = nextArmed;
      altLocked = nextLocked;
      _altTapped = locked ? null : at;
    }
  }

  /// Clears the armed (never the locked) modifiers after a key was sent;
  /// returns whether the row's highlight changed.
  bool consume() {
    if (!ctrlArmed && !altArmed) return false;
    ctrlArmed = false;
    altArmed = false;
    _ctrlTapped = null;
    _altTapped = null;
    return true;
  }
}
