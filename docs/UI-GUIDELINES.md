# UI guidelines

[中文](UI-GUIDELINES.zh-CN.md)

How Taildeck's screens behave: what a press looks like, what a request looks
like while it runs, when a value is a select and when it is a switch, and how
the app moves. Built on [prism_ui](../third_party/prism_ui); the rules below
are what keeps the Flutter client consistent as it grows.

## Button states

Every pressable surface has four states: rest, pressed, focused and disabled.
A row that starts a request adds a fifth: loading.

- **Pressed** — a tinted state layer over the surface, or a slight scale
  (0.97) for fills without ink. Use `TapFeedback` (`lib/src/widgets/controls.dart`)
  rather than a bare `PressRegion`: `PressRegion` leaves the overlay off unless
  it is given one, which reads as a dead row.
- **Focused** — the same overlay, from the keyboard or a remote; focus must stay
  visible on desktop.
- **Disabled** — dimmed label and no pointer cursor, not just a null callback.
- **Ripple/ink** — filled, tonal and text buttons come from prism_ui and carry
  their own press look; do not rebuild them.
- **Hit area** — at least 44 dp tall for anything on a phone.

```dart
TapFeedback(
  onTap: open,
  scale: true,             // glass pill or chip
  child: /* row */,
)
```

## Async actions

A button that starts work must say so in the same frame it is pressed:

1. **Loading at once** — set the busy flag before the first `await`; never show
   a second press as a no-op with no feedback.
2. **Disabled while busy** — guard the handler (`if (_busy) return;`) and pass
   `loading:` to `LoadingButton`, so a double tap cannot submit twice.
3. **No layout jump** — the spinner sits inside the button, in place of its
   glyph, at a fixed size; the label stays. `LoadingButton` keeps the button's
   height.
4. **Success or failure** — on completion show the outcome where the action
   lives: an `InlineNotice` on the page or sheet (errors), a short confirmation
   after a save, then re-enable. Never swallow an exception: keep the inline
   error text and clear it on the next attempt.
5. **Destructive work** — confirm first, then load; the confirm dialog is not a
   loading state.

Inventory of actions and where their feedback shows:

| Action | Loading | Result |
|---|---|---|
| Sign in (auth key / browser) | `LoadingButton`, browser row spinner | `InlineNotice` on failure, waiting card on browser login |
| SSH connect | `LoadingButton` in the sheet | inline error, sheet closes on success |
| Ping / scan ports | `ActionPill` spinner, pill disabled | ping label, scan result or `InlineNotice` |
| Save / add / edit service | `LoadingButton` in the sheet | sheet closes, page confirmation; error stays inline |
| Delete service | spinner in the row | row collapses, confirmation notice |
| Import key | `LoadingButton` in the sheet | key list refreshes, inline error on failure |
| Forget host keys | row spinner, row disabled | confirmation notice or error |
| Sign out | confirm, then the shell leaves the screen | login screen |
| Agent connect / send / restart / model | button or icon spinner, controls disabled | notice or inline notice with the error |
| Agent notifications | switch replaced by a spinner | switch returns on the saved value |

## Selects and segmentation

`SelectRow` (`lib/src/widgets/select_row.dart`) is the one control for choosing
a value inside a form: SSH auth method, port, identity, service node, scheme,
theme, language, bottom bar style, tab animation, service open mode, agent
harness/workspace/model.

- It opens prism_ui's `PopupAnchor` + `PopupMenu` (the iOS-style menu) with a
  check on the current value, and reads as one item: "label, value" plus a
  select hint.
- Disable it with `enabled: false` while its form is submitting.
- `SegmentedControl` is only for switching a view or filter (segments of the
  same screen), never for a form value: a segmented row says "show me this",
  a select says "save this".

## Motion

| What | Duration | Curve |
|---|---|---|
| Page push (desktop) | 200 ms fade | prism_ui `FadePageRoute` |
| Page push (mobile) | spring card route | prism_ui `CardPageRoute`, drag-back |
| List row enter/exit | 220 ms size + fade | `easeInOutCubic`, via `AnimatedGroupCard` |
| Section reveal on open | 200 ms fade + 8 dp lift | `easeOutCubic`, 32 ms stagger, 160 ms cap |
| Select / sheet | prism_ui's own route motion | — |
| Press overlay | 50 ms | — |

- Lists that can change while visible (services, agents, nodes) use
  `AnimatedGroupCard`; the separator belongs to the row above, so it leaves
  with the row.
- Reduce motion: `context.disableAnimations` (the system setting or
  `?motion=off`) makes reveals, lists and routes instant. Any new animation
  must check it; prism_ui's own widgets already do.
- Do not animate more than one thing at a time on a phone: a page push and a
  list reveal should not overlap.

## Accessibility

- One screen-reader node per row: `RowSemantics(label: ...)` or the semantic
  label on `TapFeedback`/`SelectRow`; do not read the raw pieces.
- Buttons carry an action label ("Connect", "Scan common ports"), selects read
  "label, value" and the `Select` hint, sheets have a title and a close label.
- The loading button reports its busy value, so a screen reader hears that the
  action is running.
- Focus is visible and Esc leaves pages and sheets (handled by prism_ui).
- Text follows the system text scale; rows grow instead of clipping.
- Colour is never the only signal: a status also has a word.

## Icons

- Source of truth: prism_ui's `Glyphs` plus the app's `Glyphs2`
  (`lib/src/glyphs.dart`). No Material `Icons`, no emoji, no image assets for
  UI.
- Sizes: 14–16 in rows, 18 in buttons, 22–28 for a page or card badge.
- Colour: `onSurfaceVariant` for quiet icons, the node/service tint for
  identity, `scheme.error` only for destructive actions.
- Status uses a glyph plus a word (`StatusPill`), never a glyph alone.

## Copy

- Chinese and English ship together; every new string goes through
  `AppLocalizations` in the same change.
- Sentence case, no exclamation marks, no "new ✨". Say what the action does:
  "Scan common ports", not "Scan".
- Errors name the thing that failed and keep the server's detail:
  "Save failed: <reason>". Do not blame the user.
- Counts and dates use the app's own formatting (`l10n.lastSeen`, `shortDate`),
  not `intl` patterns.
