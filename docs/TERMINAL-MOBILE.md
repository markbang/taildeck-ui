# Terminal on a phone: keys, gestures and the keyboard

A soft keyboard has no Esc, Ctrl, Alt, Tab or arrows, so every mobile terminal
ships some accessory strip and a set of grid gestures. This note records what
the reference apps do, what Taildeck builds on top of libghostty-vt, and what is
still missing.

Sources were read on 2026-11-14 and 2026-11-15. Terms used below: **row** is
the strip that sits between the terminal and the soft keyboard; **page** is one
screenful of keys inside that row.

## Reference behaviour

| App | Accessory keys | Sticky modifiers | Pages / more keys | Customization |
| --- | --- | --- | --- | --- |
| Termius (iOS, Android) | Keyboard add-on directly above the system keyboard, always visible while typing; it shows the first three groups of the extended keyboard | Ctrl, Esc, Tab and other modifiers in the extended keyboard | Extended keyboard (side panel) holds the full list: arrows, function keys, symbols, navigation keys | Key groups of four: reorder groups, create custom groups, drop the hide-keyboard button |
| Blink Shell (iOS) | Smart Keys, visible only while the on-screen keyboard is up, hidden with a hardware keyboard | Ctrl, Alt, Esc; a held modifier chains several combinations (C-x C-c) | Scrollable area in the middle of the bar for more keys | `config` → Keyboard: remap modifiers (left and right separately), turn single presses into sequences |
| JuiceSSH (Android, discontinued) | Popup keyboard overlaid on the terminal: Ctrl, Alt, Tab, arrows and the hard-to-type characters | Ctrl and Alt are toggles; the Alt key can be made to send Esc instead | Swipe the popup right for autocomplete, left to return; "Popup keyboard position" moves it | Vibrate on key press, popup position, Alt mode |
| Termux (Android) | Extra keys view, toggled from the drawer or Volume-Up+Q/K; two rows by default | CTRL, ALT, FN, SHIFT as special keys; Volume-Down emulates Ctrl | `extra-keys` takes a list of rows; swipe up on a key for its popup (e.g. `{key: LEFT, popup: HOME}`); swiping the row left opens the text input view | `~/.termux/termux.properties`: `extra-keys`, `extra-keys-style`; `termux-reload-settings` applies it |

### Herdr: focus, click and mouse reporting

Herdr is a desktop terminal multiplexer, so it has no touch layer: neither
`herdrdev/herdr-core` nor `herdrdev/herdr-app` has a tap-to-focus or
soft-keyboard rule. Its pointer path is still the reference for what a click
must send, and Termius and Blink supply the keyboard rules.

- `herdr-app`'s terminal view focuses itself on left mouse down, before
  anything else, then resizes the core to the grid it is about to draw.
- The same click is offered to the program: if the emulator reports mouse
  tracking (and Shift is not held, which keeps the mouse for the app) it sends
  a press with the button and modifiers, and clears the local selection; if
  the program does not track the mouse it starts a local selection instead
  (press, drag motion, release, copy-on-select).
- Motion goes out only while a button is held; the release only for a button
  the view recorded as down, and `any_button_pressed` is set for the whole
  drag. A wheel notch is button 4/5 at the middle of the screen, and comes back
  empty when the program does not track the mouse.
- `herdr-core`'s encoder is `ghostty_mouse_encoder_setopt_from_terminal`, so
  the report format is whatever the remote asked for — X10, UTF-8, SGR 1006,
  URxvt or SGR-Pixels — and the position is in surface pixels with the cell
  size; the encoder derives the 1-based cell.
- The focused terminal is also where the OS input method types (Pinyin,
  Japanese, dead keys), the same way our input line owns the IME.

On a phone the keyboard rules come from the reference apps instead: Termius
says the on-screen keyboard appears when the terminal input is focused and
hides with a hardware keyboard, and that Hide Keyboard lives on the keyboard
add-on, not on a tap. Blink's Smart Keys are only visible while the keyboard
is up. That is why a tap here always shows the keyboard and never hides it.

## What Taildeck does now

| Feature | Reference | Our plan / implementation | Status |
| --- | --- | --- | --- |
| Row placement | Termius puts the add-on directly above the system keyboard and keeps it while typing | Docked at the bottom of the terminal page, under the input line and above the soft keyboard. The page pads by `MediaQuery.viewInsets` on every platform (nothing above it builds a `Scaffold` that would resize), and the terminal grid shrinks with the row, so the cursor stays visible. A desktop window has a hardware keyboard, so it hides the row | Implemented |
| Keys | Termius: modifiers, arrows, function and symbol keys. Termux: a fixed two-row default | Page 1: Esc, Tab, Ctrl, Alt, ←, ↑, ↓, →. Page 2: Home, End, PgUp, PgDn, `\|`, `~`, `/`, `-`. Page 3: `_`, `:`, `*`, `&`, `=`, `?`, `'`, `\` | Implemented |
| Encoding | — | Every key goes through libghostty-vt's encoder (`td_term_encode_key`) with the armed modifiers, so Alt and Ctrl produce what the running program expects | Implemented |
| Send | Termius and Blink use the keyboard's own Enter; JuiceSSH has no input line to send | The input line is the buffer: Send, or the soft keyboard's send/done key, writes the text and then one CR per line, so a three-line paste runs three commands 20 ms apart. A long-press on Send, or the row's `Ins` key, inserts without Enter and keeps that choice in the app config. Bracketed paste from the selection toolbar stays literal | Implemented |
| Sticky modifiers | Blink: hold a modifier to chain. Termux: CTRL/ALT are special keys | One tap arms Ctrl/Alt and highlights the key; the next key (row key or typed character) carries the modifier and clears the highlight | Implemented |
| Modifier lock | JuiceSSH: Alt can be set to send Esc permanently | Double-tap locks the modifier (stronger highlight, stays armed); a further tap clears it | Implemented |
| Pages | Termux: `extra-keys` rows, swipe for the rest. JuiceSSH: swipe right/left on the popup | Horizontal swipe between pages, plus tappable page dots for keyboards and screen readers | Implemented |
| Customization | Termius: reorder and custom groups. Termux: `extra-keys` in a properties file. Blink: `config` → Keyboard | Settings → Terminal → Extra key row: toggle which keys each page shows (a key belongs to one page), reset to defaults, persisted in the app config | Implemented |
| Haptics | JuiceSSH: "Vibrate Device" | `HapticFeedback.lightImpact` on every press, with Settings → Terminal → "Terminal key haptics" | Implemented |
| Held keys | Arrow keys repeat while held on a hardware keyboard | Holding ←, ↑, ↓ or → on the row repeats it: first after 380 ms, then every 70 ms; the release sends nothing extra | Implemented |
| Tap to focus | Termius: the keyboard appears when the terminal input is focused, and only the add-on's Hide Keyboard or the system puts it away. Herdr: a click focuses the view before it is sent anywhere | A tap on the grid focuses the input line and shows the soft keyboard, on every tap; it never hides it. A second tap, a tap on blank space, a long press and a double tap all keep it. When Android dismissed the IME but the field kept focus, the tap takes focus anew (one frame unfocused, then focused), because `TextInput.show` alone is ignored for an unchanged focus. The key row's keyboard button and the system back are the only ways to hide it; the button calls `TextInput.hide` and keeps focus, so a hardware keyboard still types | Implemented |
| Mouse reporting | Herdr: a click in a tracking program is a press then release with the button and modifiers; Shift keeps it local; a long press is local selection | A tap in a program that tracks the mouse sends a left press and a release through `td_term_encode_mouse`: the tap pixel and the current cell size give the cell, the key row's armed Ctrl/Alt ride along as GhosttyMods bits, and they clear after the click. The emulator picks the protocol the remote enabled (SGR 1006 is what vim, htop and tmux ask for); a terminal without mouse tracking gets no bytes. Long-press and double-tap are local selection and never send a click | Implemented |
| Wheel and drag | Herdr: wheel notches are button 4/5 reports when the mouse is tracked; drag reports motion | A vertical drag walks the scrollback and a wheel scrolls it, locally. Reporting the wheel to a tracking program is not done yet | Open |
| Grid gestures | Termius puts its gestures on the grid; Termux swipes its row | A one-finger swipe sends arrow keys. The axis locks to the first movement, one key per 26 dp along it, at most three per frame. Settings → Terminal → "Swipe sends arrows" turns it off, and a vertical drag then walks the scrollback | Implemented |
| Word selection | Kotlin `TerminalView` selects the word under a long press; iOS terminals use double-tap | Long-press enters selection on the word under the finger and double-tap does the same, through `td_term_select`; two draggable handles move either end; a drag on the grid moves the far end, a tap clears the selection and keeps the keyboard up | Implemented |
| Copy, paste and links | Kotlin action mode has Copy and Paste; Termius and Blink both put copy on the selection | A toolbar over the selection: Copy (`td_term_selection_text` → system clipboard), Open link when the whole selection is one http(s) URL, Paste (`td_term_encode_paste`, bracketed paste respected). The input bar carries a paste button too | Implemented |
| Zoom | Blink: pinch on the grid | Pinch changes the grid font size from 8 to 24 pt and keeps it. Settings → Terminal shows the same value with A− / A+ | Implemented |
| Keyboard and rotation | — | Showing or hiding the soft keyboard, and rotation, resize the grid, which resizes the emulator (`td_term_resize`) and the SSH PTY (`td_ssh_resize`); the columns and rows follow the cells. After a resize the viewport returns to the live screen, so the cursor stays visible above the key row even when the scrollback was being read. Landscape below 420 dp of height drops the quick-command strip | Implemented |
| Hardware keyboard | Blink hides its Smart Keys when a keyboard is attached | Ctrl, Alt, Meta, arrows, Esc and Tab go through `td_term_encode_key` from the input line's focus node. The row hides while Android reports a physical keyboard (`Configuration.keyboard`), unless Settings → Terminal keeps it or the soft keyboard is up. iOS and desktop keep their current behaviour: desktop always hides, iOS cannot tell | Implemented |
| Snippets | Termius snippets, Blink Snips | Settings → Terminal → Snippets, or the chip at the head of the quick-command row: a name, the command line, and "Append Enter" per snippet (off types the text without running it). A tap in the terminal sends it, the panel edits it, and up/down reorder; up to 40 entries in the app config | Implemented |
| Sessions | Termius session tabs | Every SSH session stays open in the store, one per node. The emulator belongs to the session, not the page, so its scrollback and an alternate-screen program survive. With two or more sessions a strip under the header shows `user@node` with a live or dropped dot; a tap switches, and the grid returns as it was left (vim keeps its screen) | Implemented |
| Reconnect | Termius reconnect | A dropped session keeps its page, turns the status pill red and offers Reconnect in the header. One tap dials the same node, user, port and key or password, which the session holds in memory only; nothing is re-typed and the password never reaches disk | Implemented |
| Background keep-alive | Termius keeps sessions alive; the OS decides for how long | Settings → Terminal → "Keep sessions in background" (on by default). On, the Android `dataSync` foreground service keeps the process while the app is away. Off, the service stops as the app leaves the foreground and the shell ends every session. Sign-out always ends the sessions and stops the service | Implemented |
| Themes and font | Termius, Blink and JuiceSSH ship palettes; Termius and Blink ship font choices | Five palettes (Taildeck dark, Midnight, Paper light, Solarized dark, Solarized light) or "Match appearance", which takes a light palette under the app's light theme. A theme paints the whole page — header, chips, input bar, key row — and supplies the grid's default foreground and background; colors the remote sets itself stay as reported. Font: DejaVu Sans Mono, the platform monospace or Roboto (proportional); the grid re-measures cells, so columns and rows follow | Implemented |
| Cursor | DECSCUSR; iTerm and Termius expose cursor settings | Block, bar or underline, or "From the program"; a blink toggle (530 ms) draws the cursor on its own layer, so a tick never repaints the text, and reduce-motion keeps it solid | Implemented |
| Safe areas | — | The grid reaches the top edge; the key row and the input line own the bottom inset, so the row's surface covers the gesture bar instead of leaving a strip of page below it. In landscape the notch inset stays on the chrome rather than on the grid | Implemented |

## Verification

`tool/termtap_record.sh` (workflow `termtap-record`) is the tap gate. It
installs the APK, signs in to the runner's test control plane, opens a real
session on the peer's sshd, puts the keyboard away and taps the grid: the run
fails unless `dumpsys input_method` reports `mInputShown=true`, the terminal
window is the focused one, a second tap and a blank-space tap leave the IME up,
a command typed after the tap runs on the shell, the key row's keyboard button
hides the IME, and a tap after it shows the IME again. The same run starts a
small Python program on the peer that enables mouse tracking (1000 + SGR 1006)
and logs what it reads; the gate fails unless a tap arrives as `<0;Cx;CyM`
then `<0;Cx;Cym` on the same cell, and a Ctrl-armed tap as `<16;`.
The clips are `tap-focus.mp4` (IME put away, tap, keyboard up, second tap),
`tap-mouse.mp4` and `tap-mouse-ctrl.mp4` (the probe's reports on the grid),
`tap-vim.mp4` with `tap-vim-before.png` / `tap-vim-after.png` (vim started with
`set mouse=a`; a tap with the keyboard already up moves the cursor to another
cell) and `tap-htop.mp4` with `tap-htop-before.png` / `tap-htop-after.png` (a
tap on one process row, then on another). Stills: `tap-keyboard.png`.

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

The Android stills and clips come from the `termsessions-record` run: a real
session on the runner's peer (`term-android-session.png`), a snippet that ran
`df -h /` there (`term-android-snippet.png`, `term-snippets.mp4`), two
sessions in the strip (`term-android-sessions.png`,
`term-sessions-switch.mp4`) and the theme switch through Settings
(`term-theme.mp4`, `term-android-settings.png`).

The tap gate cannot use a real finger: `adb shell input tap` injects a touch
through InputManager. A long press, a double tap and a drag still go through
the app's own recognisers, but the emulator's two-finger contact is not a real
pinch, so zoom stays unexercised. The mouse gate covers the SGR
1006 form that vim, htop and tmux ask for; the other formats the ghostty
encoder knows (X10, UTF-8, URxvt, SGR-Pixels) are only covered by
`tool/term_smoke.dart` for the SGR case. Mouse motion reports during a drag,
wheel reports, and right/middle click are not implemented, so nothing exercises
them.

Two things were not exercised. The Android build, its foreground service and
the display cutout need the emulator run: the desktop window has no notch, no
gesture bar and no `dataSync` service, so the safe-area result and the
keep-alive toggle are still open. The emulator run also skipped the cursor and
font rows: its taps landed under the floating dock, so those stills are the
desktop renderer's.
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

`tool/termsend_record.sh` (workflow `termsend-record`) records what Send
writes. The demo session echoes every byte with caret notation, so the CR shows
on the grid as `^M`: `term-send-button.png` is the input line's Send
(`echo send^M`), `term-send-ime.png` the soft keyboard's Enter
(`echo enter^M`), `term-send-ime-action.png` Gboard's own send key
(`echo action^M`, tap point found by colour because the keyboard keeps its keys
out of the accessibility tree), and `term-send-insert.png` with
`-insert-cr.png` the long-press that inserts `echo ins` without Enter and then
sends the bare CR alone. The clips are the matching `term-send-*.mp4`. No
tailnet was reachable from the emulator, so no shell ran those lines: a real
`echo` output, history recall and completion are unverified.


## Sources

- Herdr, `herdrdev/herdr-core` — the ghostty-vt mouse encoder, its wheel reports and the input gate: <https://github.com/herdrdev/herdr-core> (read 2026-11-15, `crates/ghostty-vt/src/lib.rs`, `crates/herdr-core/src/input.rs`)
- Herdr, `herdrdev/herdr-app` — the terminal view's focus, click, selection and motion path: <https://github.com/herdrdev/herdr-app> (read 2026-11-15, `src/terminal.rs`)
- Termius, *Mobile terminal* — keyboard add-on, extended keyboard, key groups, volume buttons, gestures: <https://docs.termius.com/terminal/mobile-terminal>
- Blink Shell, *Quick Start* (docs home) — Smart Keys, modifier chaining, scrollable middle area: <https://docs.blink.sh/>
- Blink Shell, *Customizing Blink Shell* — modifiers, custom presses, keyboard settings: <https://docs.blink.sh/basics/customize>
- JuiceSSH, English strings (popup keyboard with Ctrl/Alt/Tab, swipe to autocomplete, vibrate on key press, Alt sends Esc): <https://github.com/Sonelli/juicessh-translations/blob/master/en_GB/strings.xml> — the app is discontinued and `juicessh.com` is now a parked domain, so its string resources are the surviving primary source
- Termux, *Touch Keyboard* — extra keys row, `extra-keys` pages, popups, `extra-keys-style`: <https://wiki.termux.com/wiki/Touch_Keyboard>
- Flutter `HapticFeedback.lightImpact`: <https://api.flutter.dev/flutter/services/HapticFeedback/lightImpact.html>
- Termius, *Gestures* — double-tap, long-press and swipe on the grid: <https://docs.termius.com/terminal/mobile-terminal>
- Flutter `ScaleGestureRecognizer` (the pinch and the one-finger swipe): <https://api.flutter.dev/flutter/gestures/ScaleGestureRecognizer-class.html>
- Android `Configuration.keyboard` — the physical-keyboard bit the key row reads: <https://developer.android.com/reference/android/content/res/Configuration#keyboard>
