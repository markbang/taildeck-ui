# Terminal on a phone: the extra key row

A soft keyboard has no Esc, Ctrl, Alt, Tab or arrows, so every mobile terminal
ships some accessory strip. This note records what the reference apps do, what
Taildeck builds on top of libghostty-vt, and what is still missing.

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
| Row placement | Termius puts the add-on directly above the system keyboard and keeps it while typing | Docked at the bottom of the terminal page, under the input line and above the soft keyboard. Android's `adjustResize` already shrinks the view; iOS gets the keyboard as a `viewInsets` pad. The terminal grid shrinks with the row, so the cursor stays visible. A desktop window has a hardware keyboard, so it hides the row | Implemented |
| Keys | Termius: modifiers, arrows, function and symbol keys. Termux: a fixed two-row default | Page 1: Esc, Tab, Ctrl, Alt, ←, ↑, ↓, →. Page 2: Home, End, PgUp, PgDn, `\|`, `~`, `/`, `-`. Page 3: `_`, `:`, `*`, `&`, `=`, `?`, `'`, `\` | Implemented |
| Encoding | — | Every key goes through libghostty-vt's encoder (`td_term_encode_key`) with the armed modifiers, so Alt and Ctrl produce what the running program expects | Implemented |
| Sticky modifiers | Blink: hold a modifier to chain. Termux: CTRL/ALT are special keys | One tap arms Ctrl/Alt and highlights the key; the next key (row key or typed character) carries the modifier and clears the highlight | Implemented |
| Modifier lock | JuiceSSH: Alt can be set to send Esc permanently | Double-tap locks the modifier (stronger highlight, stays armed); a further tap clears it | Implemented |
| Pages | Termux: `extra-keys` rows, swipe for the rest. JuiceSSH: swipe right/left on the popup | Horizontal swipe between pages, plus tappable page dots for keyboards and screen readers | Implemented |
| Customization | Termius: reorder and custom groups. Termux: `extra-keys` in a properties file. Blink: `config` → Keyboard | Settings → Terminal → Extra key row: toggle which keys each page shows (a key belongs to one page), reset to defaults, persisted in the app config | Implemented |
| Haptics | JuiceSSH: "Vibrate Device" | `HapticFeedback.lightImpact` on every press, with Settings → Terminal → "Terminal key haptics" | Implemented |
| Copy / paste, selection | Termius and Blink both put these on gestures | Not in this change | Later |
| Gesture shortcuts (long-press drag for arrows, double-tap for Tab) | Termius | Not in this change | Later |
| Snippets, sessions, custom key sequences | Termius snippets, Blink Snips | Not in this change | Later |

## Sources

- Termius, *Mobile terminal* — keyboard add-on, extended keyboard, key groups, volume buttons, gestures: <https://docs.termius.com/terminal/mobile-terminal>
- Blink Shell, *Quick Start* (docs home) — Smart Keys, modifier chaining, scrollable middle area: <https://docs.blink.sh/>
- Blink Shell, *Customizing Blink Shell* — modifiers, custom presses, keyboard settings: <https://docs.blink.sh/basics/customize>
- JuiceSSH, English strings (popup keyboard with Ctrl/Alt/Tab, swipe to autocomplete, vibrate on key press, Alt sends Esc): <https://github.com/Sonelli/juicessh-translations/blob/master/en_GB/strings.xml> — the app is discontinued and `juicessh.com` is now a parked domain, so its string resources are the surviving primary source
- Termux, *Touch Keyboard* — extra keys row, `extra-keys` pages, popups, `extra-keys-style`: <https://wiki.termux.com/wiki/Touch_Keyboard>
- Flutter `HapticFeedback.lightImpact`: <https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html>
