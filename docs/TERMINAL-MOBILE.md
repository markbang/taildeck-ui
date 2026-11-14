# Terminal on a phone: keys, gestures and the keyboard

A soft keyboard has no Esc, Ctrl, Alt, Tab or arrows, so every mobile terminal
ships some accessory strip and a set of grid gestures. This note records what
the reference apps do, what Taildeck builds on top of libghostty-vt, and what is
still missing.

Sources were read on 2026-11-14. Terms used below: **row** is the strip that
sits between the terminal and the soft keyboard; **page** is one screenful of
keys inside that row.

## Reference behaviour

| App | Accessory keys | Sticky modifiers | Pages / more keys | Customization |
| --- | --- | --- | --- | --- |
| Termius (iOS, Android) | Keyboard add-on directly above the system keyboard, always visible while typing; it shows the first three groups of the extended keyboard | Ctrl, Esc, Tab and other modifiers in the extended keyboard | Extended keyboard (side panel) holds the full list: arrows, function keys, symbols, navigation keys | Key groups of four: reorder groups, create custom groups, drop the hide-keyboard button |
| Blink Shell (iOS) | Smart Keys, visible only while the on-screen keyboard is up, hidden with a hardware keyboard | Ctrl, Alt, Esc; a held modifier chains several combinations (C-x C-c) | Scrollable area in the middle of the bar for more keys | `config` → Keyboard: remap modifiers (left and right separately), turn single presses into sequences |
| JuiceSSH (Android, discontinued) | Popup keyboard overlaid on the terminal: Ctrl, Alt, Tab, arrows and the hard-to-type characters | Ctrl and Alt are toggles; the Alt key can be made to send Esc instead | Swipe the popup right for autocomplete, left to return; "Popup keyboard position" moves it | Vibrate on key press, popup position, Alt mode |
| Termux (Android) | Extra keys view, toggled from the drawer or Volume-Up+Q/K; two rows by default | CTRL, ALT, FN, SHIFT as special keys; Volume-Down emulates Ctrl | `extra-keys` takes a list of rows; swipe up on a key for its popup (e.g. `{key: LEFT, popup: HOME}`); swiping the row left opens the text input view | `~/.termux/termux.properties`: `extra-keys`, `extra-keys-style`; `termux-reload-settings` applies it |

## What Taildeck does now

| Feature | Reference | Our plan / implementation | Status |
| --- | --- | --- | --- |
| Row placement | Termius puts the add-on directly above the system keyboard and keeps it while typing | Docked at the bottom of the terminal page, under the input line and above the soft keyboard. The page pads by `MediaQuery.viewInsets` on every platform (nothing above it builds a `Scaffold` that would resize), and the terminal grid shrinks with the row, so the cursor stays visible. A desktop window has a hardware keyboard, so it hides the row | Implemented |
| Keys | Termius: modifiers, arrows, function and symbol keys. Termux: a fixed two-row default | Page 1: Esc, Tab, Ctrl, Alt, ←, ↑, ↓, →. Page 2: Home, End, PgUp, PgDn, `\|`, `~`, `/`, `-`. Page 3: `_`, `:`, `*`, `&`, `=`, `?`, `'`, `\` | Implemented |
| Encoding | — | Every key goes through libghostty-vt's encoder (`td_term_encode_key`) with the armed modifiers, so Alt and Ctrl produce what the running program expects | Implemented |
| Sticky modifiers | Blink: hold a modifier to chain. Termux: CTRL/ALT are special keys | One tap arms Ctrl/Alt and highlights the key; the next key (row key or typed character) carries the modifier and clears the highlight | Implemented |
| Modifier lock | JuiceSSH: Alt can be set to send Esc permanently | Double-tap locks the modifier (stronger highlight, stays armed); a further tap clears it | Implemented |
| Pages | Termux: `extra-keys` rows, swipe for the rest. JuiceSSH: swipe right/left on the popup | Horizontal swipe between pages, plus tappable page dots for keyboards and screen readers | Implemented |
| Customization | Termius: reorder and custom groups. Termux: `extra-keys` in a properties file. Blink: `config` → Keyboard | Settings → Terminal → Extra key row: toggle which keys each page shows (a key belongs to one page), reset to defaults, persisted in the app config | Implemented |
| Haptics | JuiceSSH: "Vibrate Device" | `HapticFeedback.lightImpact` on every press, with Settings → Terminal → "Terminal key haptics" | Implemented |
| Held keys | Arrow keys repeat while held on a hardware keyboard | Holding ←, ↑, ↓ or → on the row repeats it: first after 380 ms, then every 70 ms; the release sends nothing extra | Implemented |
| Grid gestures | Termius puts its gestures on the grid; Termux swipes its row | A one-finger swipe sends arrow keys. The axis locks to the first movement, one key per 26 dp along it, at most three per frame. Settings → Terminal → "Swipe sends arrows" turns it off, and a vertical drag then walks the scrollback | Implemented |
| Word selection | Kotlin `TerminalView` selects the word under a long press; iOS terminals use double-tap | Double-tap or long-press selects the word under the finger through `td_term_select`; two draggable handles move either end; a drag on the grid moves the far end, a tap clears | Implemented |
| Copy, paste and links | Kotlin action mode has Copy and Paste; Termius and Blink both put copy on the selection | A toolbar over the selection: Copy (`td_term_selection_text` → system clipboard), Open link when the whole selection is one http(s) URL, Paste (`td_term_encode_paste`, bracketed paste respected). The input bar carries a paste button too | Implemented |
| Zoom | Blink: pinch on the grid | Pinch changes the grid font size from 8 to 24 pt and keeps it. Settings → Terminal shows the same value with A− / A+ | Implemented |
| Keyboard and rotation | — | Showing or hiding the soft keyboard, and rotation, resize the grid, which resizes the emulator (`td_term_resize`) and the SSH PTY; the columns and rows follow the cells, so the cursor stays above the key row. Landscape below 420 dp of height drops the quick-command strip | Implemented |
| Hardware keyboard | Blink hides its Smart Keys when a keyboard is attached | Ctrl, Alt, Meta, arrows, Esc and Tab go through `td_term_encode_key` from the input line's focus node. The row hides while Android reports a physical keyboard (`Configuration.keyboard`), unless Settings → Terminal keeps it or the soft keyboard is up. iOS and desktop keep their current behaviour: desktop always hides, iOS cannot tell | Implemented |
| Snippets, sessions, custom key sequences | Termius snippets, Blink Snips | Not in this change | Later |

## Sources

- Termius, *Mobile terminal* — keyboard add-on, extended keyboard, key groups, volume buttons, gestures: <https://docs.termius.com/terminal/mobile-terminal>
- Blink Shell, *Quick Start* (docs home) — Smart Keys, modifier chaining, scrollable middle area: <https://docs.blink.sh/>
- Blink Shell, *Customizing Blink Shell* — modifiers, custom presses, keyboard settings: <https://docs.blink.sh/basics/customize>
- JuiceSSH, English strings (popup keyboard with Ctrl/Alt/Tab, swipe to autocomplete, vibrate on key press, Alt sends Esc): <https://github.com/Sonelli/juicessh-translations/blob/master/en_GB/strings.xml> — the app is discontinued and `juicessh.com` is now a parked domain, so its string resources are the surviving primary source
- Termux, *Touch Keyboard* — extra keys row, `extra-keys` pages, popups, `extra-keys-style`: <https://wiki.termux.com/wiki/Touch_Keyboard>
- Flutter `HapticFeedback.lightImpact`: <https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html>
- Termius, *Gestures* — double-tap, long-press and swipe on the grid: <https://docs.termius.com/terminal/mobile-terminal>
- Flutter `ScaleGestureRecognizer` (the pinch and the one-finger swipe): <https://api.flutter.dev/flutter/gestures/ScaleGestureRecognizer-class.html>
- Android `Configuration.keyboard` — the physical-keyboard bit the key row reads: <https://developer.android.com/reference/android/content/res/Configuration#keyboard>
