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
| Snippets | Termius snippets, Blink Snips | Settings → Terminal → Snippets, or the chip at the head of the quick-command row: a name, the command line, and "Append Enter" per snippet (off types the text without running it). A tap in the terminal sends it, the panel edits it, and up/down reorder; up to 40 entries in the app config | Implemented |
| Sessions | Termius session tabs | Every SSH session stays open in the store, one per node. The emulator belongs to the session, not the page, so its scrollback and an alternate-screen program survive. With two or more sessions a strip under the header shows `user@node` with a live or dropped dot; a tap switches, and the grid returns as it was left (vim keeps its screen) | Implemented |
| Reconnect | Termius reconnect | A dropped session keeps its page, turns the status pill red and offers Reconnect in the header. One tap dials the same node, user, port and key or password, which the session holds in memory only; nothing is re-typed and the password never reaches disk | Implemented |
| Background keep-alive | Termius keeps sessions alive; the OS decides for how long | Settings → Terminal → "Keep sessions in background" (on by default). On, the Android `dataSync` foreground service keeps the process while the app is away. Off, the service stops as the app leaves the foreground and the shell ends every session. Sign-out always ends the sessions and stops the service | Implemented |
| Themes and font | Termius, Blink and JuiceSSH ship palettes; Termius and Blink ship font choices | Five palettes (Taildeck dark, Midnight, Paper light, Solarized dark, Solarized light) or "Match appearance", which takes a light palette under the app's light theme. A theme paints the whole page — header, chips, input bar, key row — and supplies the grid's default foreground and background; colors the remote sets itself stay as reported. Font: DejaVu Sans Mono, the platform monospace or Roboto (proportional); the grid re-measures cells, so columns and rows follow | Implemented |
| Cursor | DECSCUSR; iTerm and Termius expose cursor settings | Block, bar or underline, or "From the program"; a blink toggle (530 ms) draws the cursor on its own layer, so a tick never repaints the text, and reduce-motion keeps it solid | Implemented |
| Safe areas | — | The grid reaches the top edge; the key row and the input line own the bottom inset, so the row's surface covers the gesture bar instead of leaving a strip of page below it. In landscape the notch inset stays on the chrome rather than on the grid | Implemented |

## Verification

`tool/termgestures_record.sh` (workflow `termgestures-record`) records the
gesture layer on the Android emulator: swipe arrows on both axes, a held arrow
key, word selection with its handles, copy with the toolbar's confirmation
(`term-copy.png`), opening the URL a selection holds — Chrome came to the front
(`term-open-link.png`) — landscape (`term-landscape.png`, the grid reflows to
105×12), the soft keyboard shrinking the grid with the cursor still above the
key row (`term-keyboard.png`, then `-keyboard-hidden.png`), and the font size
stepping from Settings and surviving a relaunch (`term-font.png`).

Two rows come from the Linux build with a real keyboard, because the emulator
routes injected key events to Gboard: `term-hardware.png` (Esc, Tab, Ctrl+C and
the arrows encode to `^[`, `^I`, `^C`, `^[[D`, `^[[A`) and `term-paste.png`.
The clips next to them are `docs/screenshots/term-*.mp4`.

`tool/termsessions_record.sh` (workflow `termsessions-record`) drives the same
flows on the emulator against a real shell: the recording runner starts a test
control plane plus two peer nodes whose `motion_peer` now serves SSH on port 22
(any key or password, bash on a pty), so the app dials a genuine session.

The desktop build ran the same flows against that tailnet from this machine,
which is what the stills under `docs/screenshots/term-*` show: a live prompt,
`htop` on the alternate screen (`term-htop.png`), vim in insert mode with CJK
(`term-vim.png`), a snippet that ran `df -h /autodl-fs` on the remote
(`term-snippet-sent.png`), two sessions in the strip with the first one's
scrollback intact after switching (`term-sessions.png`), the red Disconnected
state with Reconnect (`term-reconnect.png`) and the same session back after one
tap (`term-reconnect-restored.png`). Theme, font and cursor stills come from
the same native renderer (`term-theme-*.png`, `term-font-sans.png`,
`term-cursor-*.png`), and the Settings rows from the app
(`term-settings-appearance.png`, `term-settings-applied.png`).

Two things were not exercised. The Android build, its foreground service and
the display cutout need the emulator run: the desktop window has no notch, no
gesture bar and no `dataSync` service, so the safe-area result and the
keep-alive toggle are shown by the script's own stills rather than here.
Typing quickly into the input bar in the desktop build repeats a character now
and then (GTK delivers the same key twice while the buffer is being cleared);
it is the input line, not the session, and one character per 400 ms types
cleanly.

What the emulator could not exercise: the pinch itself. Its touch input is a
set of `virtio_input_multi_touch_*` devices without `INPUT_PROP_DIRECT`, so
injected two-finger contacts reach the app as mouse drags, and `adb shell
input` has no multi-pointer command. The zoom maths are covered by
`test/terminal_gestures_test.dart`, and Settings exercises the same setter and
the same grid resize. No tailnet was reachable from here either, so nothing ran
against a real shell (vim, htop, tmux).

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
