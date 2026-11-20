/// Keyboard input for the terminal page: hardware keys and the soft keyboard's
/// hidden text field, both through libghostty-vt's key encoder, with the key
/// row's armed Ctrl/Alt applied to the next key from either.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'native/keys.dart';
import 'native/term.dart';
import 'terminal_keys.dart';

class TerminalInput {
  TerminalInput({
    required this.ime,
    required this.mods,
    required this.term,
    required this.deliver,
    required this.onModsConsumed,
  }) {
    ime.addListener(_onImeChanged);
  }

  /// The hidden IME target. The field keeps what the remote received as text,
  /// so a backspace in the IME reaches the remote as a real deletion.
  final TextEditingController ime;
  final TerminalMods mods;
  final NativeTerm? Function() term;
  final void Function(Uint8List? bytes) deliver;

  /// An armed modifier was used up, so the key row's highlight changes.
  final VoidCallback onModsConsumed;

  /// The field's text at the last commit, as the remote has it.
  String _snap = '';

  /// The field's text at the last change, composing or not: what tells a new
  /// key apart from a composition that was only committed.
  String _seen = '';
  bool _resetting = false;

  void dispose() => ime.removeListener(_onImeChanged);

  void clear() => _reset('');

  /// A hardware key. While the IME target holds focus ([typing]), a plain
  /// printable key or Enter belongs to that field, whose change handler sends
  /// it; everything else (Esc, Tab, arrows, Ctrl combinations, Backspace) is
  /// a terminal key here. [held] is the hardware modifier mask.
  KeyEventResult onKey(
    KeyEvent event, {
    required bool typing,
    required int held,
  }) {
    final term = this.term();
    if (term == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final text = event.character;
    final printable =
        text != null && text.isNotEmpty && text.codeUnitAt(0) >= 0x20;
    if (printable && held & ~GhosttyMods.shift == 0) {
      if (typing) return KeyEventResult.ignored;
      _send(term, ghosttyKeyForText(text), mods.mask, text);
      return KeyEventResult.handled;
    }
    final key = ghosttyKeyOf(event);
    if (key == GhosttyKeys.enter && held == 0) {
      if (typing) return KeyEventResult.ignored;
      _send(term, GhosttyKeys.enter, mods.mask, null);
      return KeyEventResult.handled;
    }
    _send(term, key, held | mods.mask, null);
    return KeyEventResult.handled;
  }

  /// An armed modifier is spent once the key produced bytes, so a bare Shift
  /// or Ctrl press does not use it up.
  void _send(NativeTerm term, int key, int mask, String? text) {
    final encoded = _encode(term, key, mask, text);
    if (encoded == null || encoded.isEmpty) return;
    deliver(encoded);
    if (mask & mods.mask != 0 && mods.consume()) onModsConsumed();
  }

  /// Removed characters are Backspace presses and appended ones are typed
  /// keys. A composition in progress is left to the IME until it commits,
  /// except while a modifier is armed: then the key just typed is the chord at
  /// once, whatever was composed before it goes out as text, and the chord's
  /// character is taken back out of the field. An IME that composes every
  /// letter (autocorrect, suggestions, pinyin) would otherwise hold the "c" of
  /// Ctrl+C, or send it raw on commit.
  void _onImeChanged() {
    if (_resetting) return;
    final value = ime.value;
    final text = value.text;
    final seen = _seen;
    _seen = text;
    final mask = mods.mask;
    final term = this.term();
    String? chord;
    if (mask != 0 &&
        term != null &&
        text.length > seen.length &&
        text.startsWith(seen)) {
      chord = String.fromCharCode(text.substring(seen.length).runes.last);
    }
    if (chord == null && value.composing.isValid) return;
    if (term == null) {
      _snap = text;
      return;
    }
    final kept = chord == null
        ? text
        : text.substring(0, text.length - chord.length);
    if (kept != _snap) _sendDiff(term, _snap, kept);
    _snap = kept;
    if (chord != null) {
      _sendRune(term, chord.runes.single, mask);
      if (mods.consume()) onModsConsumed();
      _reset(kept);
      return;
    }
    // The caret stays at the end; the field is invisible, so any other
    // selection would only make a later diff ambiguous.
    if (value.selection.isValid && value.selection.end != text.length) {
      _resetting = true;
      ime.selection = TextSelection.collapsed(offset: text.length);
      _resetting = false;
    }
  }

  void _sendDiff(NativeTerm term, String from, String to) {
    var common = 0;
    while (common < to.length &&
        common < from.length &&
        to.codeUnitAt(common) == from.codeUnitAt(common)) {
      common++;
    }
    for (var i = common; i < from.length; i++) {
      deliver(term.encodeKey(GhosttyKeys.backspace, 0));
    }
    for (final rune in to.substring(common).runes) {
      _sendRune(term, rune, 0);
    }
  }

  void _sendRune(NativeTerm term, int rune, int mask) {
    if (rune == 0x0a || rune == 0x0d) {
      deliver(term.encodeKey(GhosttyKeys.enter, mask));
      return;
    }
    final ch = String.fromCharCode(rune);
    deliver(_encode(term, ghosttyKeyForText(ch), mask, ch));
  }

  /// Ctrl+I, Ctrl+M and Ctrl+[ by key code. libghostty-vt follows Kitty and
  /// leaves them out of its C0 table (they collide with Tab, Enter and Esc),
  /// sending CSI u or nothing. While the remote has not asked for a richer
  /// key protocol (Ctrl+A still encodes as 0x01) they get xterm's bytes, so
  /// Ctrl+[ leaves insert mode in vi.
  static const _c0 = {28: 0x09, 32: 0x0d, 3: 0x1b};
  static const _keyA = 20;

  Uint8List? _encode(NativeTerm term, int key, int mask, [String? text]) {
    final c0 = _c0[key];
    if (c0 != null && mask & ~GhosttyMods.alt == GhosttyMods.ctrl) {
      final probe = term.encodeKey(_keyA, GhosttyMods.ctrl, text: 'a');
      if (probe != null && probe.length == 1 && probe.single == 0x01) {
        return Uint8List.fromList([if (mask & GhosttyMods.alt != 0) 0x1b, c0]);
      }
    }
    return term.encodeKey(key, mask, text: text);
  }

  /// Replaces the field without sending anything. The new value carries no
  /// composing range, which makes the IME drop the composition it held.
  void _reset(String text) {
    _resetting = true;
    ime.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _resetting = false;
    _snap = text;
    _seen = text;
  }
}
