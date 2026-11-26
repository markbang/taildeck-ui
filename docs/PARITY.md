[English](PARITY.md) · [中文](PARITY.zh-CN.md)

# Parity with the Kotlin app

How much of [markbang/taildeck](https://github.com/markbang/taildeck) (Kotlin + Compose, `0d90f24`) the Flutter
client covers. The native boundary is described in [ARCHITECTURE.md](ARCHITECTURE.md); this page is only about
features.

| Status | Meaning |
|---|---|
| **Done** | Implemented and exercised here (UI screenshots, FFI smoke test, or a CI run). |
| **Unverified** | Implemented, but never exercised end to end on this machine. |
| **Partial** | Works, with a named gap. |
| **Not yet** | Missing. |

The build machine has no Tailscale control-plane access and no auth key, so anything that needs a live tailnet is
**Unverified**: real login, peer lists, SSH, herdr and port scans. The Web preview at
https://markbang.github.io/taildeck-ui/ runs on mock data; no row below counts the preview as verification.

CI's emulator gates also run the app against a test control plane and test peers (`tool/motion/`). That is an
emulator gate: not a physical device and not a live tailnet. Each row says which of these its evidence is. The
last full run of the emulator gates is [run 43937554757](https://github.com/markbang/taildeck-ui/actions/runs/43937554757)
(2026-11-16, manual dispatch, all 11 gates of that time passed). The `webvideo` and `remember` gates were added after
it; they passed in single-gate dispatches ([run 44367447671](https://github.com/markbang/taildeck-ui/actions/runs/44367447671), [run 44376405564](https://github.com/markbang/taildeck-ui/actions/runs/44376405564),
[run 44380137078](https://github.com/markbang/taildeck-ui/actions/runs/44380137078)), and no run since has covered all 13 gates.

## Demo data

The web preview and debug builds run on a fixed dataset (`lib/src/demo/`); release builds compile it out through
`demoData`, so a phone or desktop APK only ever shows what the node reports. Missing data reads as an empty state
("no agents on this node", "no nodes yet", "not connected"), never as a sample card. `tool/check_demo_free.sh`
fails a release snapshot that still carries a demo string.

## Features

| Feature | Kotlin app | Flutter client | Status | Why |
|---|---|---|---|---|
| tsnet node | In-app node via SagerNet `tsnet`, no VPN slot | Same Go engine as a c-shared library over `dart:ffi` (`native/bridge`), Android and Linux | Partial | Start/stop/status/logs work in the FFI smoke test. The node reaches Running on the test control plane in the `netready` and `routing` gates (run 43937554757); no gate has reached Tailscale's control plane |
| Login | Browser sign-in, auth key, Headscale control server | Same flows, with a waiting state and an optional control-server field | Partial | Auth-key sign-in works on the test control plane (`routing` gate, run 43937554757). Browser sign-in and approval have not run against any control server |
| Node state, peers, ping | Online, OS, addresses, tags, routes, direct/relay, latency | `td_status` / `td_ping`; last-seen and key-expiry dates localized | Partial | `netready` shows the test peer `bangwu` online (run 43937554757). A ping to a live peer is untested: the `ping` gate runs on a signed-out node and proves only that the call no longer blocks the UI |
| Node list and detail | Grouped list, detail with actions | Self card, per-OS badges, path badge, SSH/Web/Ping actions, details card | Done | UI complete and screenshotted; live values depend on the unverified node |
| SSH sessions | Tailscale SSH, password, built-in key, imported keys, OpenSSH certificates | `td_ssh_dial` + PTY, Tailscale SSH / password / key auth; leaving the terminal keeps the shell, the node resumes or disconnects it | Partial | Session plumbing and key mapping landed (M2b). The `termtap` gate opens a shell on the test peer's sshd, which accepts any key or password (`tool/motion/peer/sshd.go`), and types into it (run 43937554757). Tailscale SSH (`none` auth) and real hosts are untested. The keep-alive buffer is covered by a local test with a fake session |
| SSH auth modes | Includes OpenSSH certificates | Tailscale SSH, password, built-in ed25519 key and imported PEM keys with an optional passphrase | Partial | The ABI carries `certPath`, but the sheet has no certificate picker |
| SSH identities | Built-in key, import, delete | Built-in `id_ed25519` plus imported PEM keys, passphrase stored with metadata, delete | Done | Key creation and import paths tested locally; dialing with them is part of the unverified SSH row |
| SSH login | Editable username, kept with the saved profile | Same, validated, prefilled from the last login for that node/service, then the node's Tailscale user, then `root` | Done | Written to `config.json`; the Linux build read it back after a restart |
| Host-key trust | TOFU, forget trusted hosts | Same, `td_forget_host_keys` | Partial | First-use trust runs in the `termtap` gate, which dials the test peer on the emulator (run 43937554757). Forgetting trusted hosts and rejecting a changed key have not run |
| Services | Add, edit, delete, grouped by node | `services.json`, add/edit/delete with node, scheme, port, path | Done | Screenshotted; persisted through the native storage layer |
| Service icons | A letter tile per row | The site's favicon fetched through the node (`td_favicon`), ICO→PNG in Go, SVG via `flutter_svg`; disk cache with ETag, 7-day soft expiry and a 1-day negative cache; Settings toggle and "Refresh icons" | Partial | The fetch chain is covered by Go `httptest` tests (link tag, manifest, ico fallback, svg, timeout, size caps) and the UI by `/?favicons=demo`; no peer answered here, so a real site never served an icon |
| Port scan | 32 common ports through the node | `td_probe`, same port list | Unverified | Wired to the node; the Web preview says it needs a native build |
| Open a service | In-app WebView or default browser via the gateway | Follows Settings: in-app WebView on Android/iOS, default browser elsewhere, both through `127.0.0.1:18680` | Partial | The shared `gatewayUrl` and routing are wired and the fallback is screenshotted. The `webvideo` gate taps a saved http service on the node page and opens it in the in-app WebView against the test control plane (runs 44367447671, 44376405564). The default-browser path and https services are not exercised in CI |
| 18680 gateway | Loopback forward proxy, per-service origins | Same Go gateway from `bridge/` | Partial | Reused unchanged. The `webvideo` gate runs through it (runs 44367447671, 44376405564): the gate's own requests get 206 from `127.0.0.1:18680` both with the per-service Host header (`motionpeer-3000.localhost`) and as a proxy, and the WebView loads the tailnet URL `http://motionpeer:3000` with the proxy override pointing at the gateway |
| In-app WebView | Proxy-override WebView, tailnet hosts through the gateway | `webview_flutter` loading the gateway URL, with back/reload, progress and retry | Partial | Android and iOS only; desktop and web keep the system browser and say so inline. The `webvideo` emulator gate runs only on a manual full dispatch; against the test control plane it passed in single-gate dispatches (runs 44367447671, 44376405564), with H.264 and HLS clips playing past 1.5 s. No physical device has run the WebView. Downloads, file pickers and HTTP auth are not wired |
| Agents list | herdr panes by workspace, states, errors | Real `agent.list` over SSH, workspace sections, state pills; the form hides behind "Connection settings" | Partial | Startup dials once, gated on the node being Running with its peer table; opening the tab wakes a saved target once, and only a failure that dial made shows, as a human sentence with a manual Retry (nothing re-dials by itself); `tool/agents_android.sh` in `android-smoke` covers the cold start; `tool/agents_switch_record.sh` covers the tab switch, in the dispatch-only `agents-switch-record` workflow. Live panes untested |
| Agent chat | Transcript, prompt, restart, model switch, more history | Transcript or screen text, prompt, restart, `/model` and effort picker, paging | Partial | Same gap: no live herdr; see the rows below for what is missing |
| Notifications | Allow / deny / reply from a notification | `flutter_local_notifications` alert when a pane turns `blocked` or `done` while the app is away; tap opens that pane's chat; zh/en toggle in Settings | Partial | Tap-to-open only, no Allow / Deny / Reply actions yet. Built for Android and iOS; delivery and permission prompts are unverified without a device |
| Prompt queues | Queue prompts while an agent works | Holds prompts locally, sends one per settle, cancel or send now | Partial | Queued while the agent works and released on `done`/`idle`; no live herdr to watch it change the agent's turn |
| Subagent transcripts | Open a subagent's call transcript | `td_herdr_subagent` reads the pane session's subagent file, with type, description and finished state | Partial | Claude only and error states only; no live subagent ran |
| Images | Show transcript images and files the agent names | `td_herdr_image` for `img:` refs, thumbnails in the transcript, full-screen zoom view, upload of a picked file via `td_herdr_upload` | Partial | Rendering and the full-screen view are implemented; the composer has no attach button yet, and node paths (not `img:` refs) stay as placeholders |
| Slash commands | Completion for `/` commands | Built-in list per harness plus `/` commands and skills read from the node, ↑↓/Esc, inserts the chosen command | Partial | Popup verified against the built-in list; node commands untested without a node |
| Settings and logs | Tailnet, device, services, SSH keys, logs | A grouped list (Tailnet & device, SSH identities, Services, Notifications, Terminal, Theme, Language, Logs, About): enumerated values pick from a menu anchored at the row, the rest open a page by growing the row's card into it, as FlClash's OpenContainer does; the theme page previews the theme and its mode choices. A subpage names itself in a compact floating bar (circular back, one line of title, the page's actions at its end) and its content scrolls under it; a first-level list hands its large title to that bar as it scrolls | Done | Screenshotted and recorded against FlClash on the emulator (`tool/screenshots_android.sh`, `tool/settings_flclash_record.sh`, `tool/header_flclash_record.sh`) |
| Sign out | Stop and log out the node | `td_logout` with a confirmation | Unverified | Needs a signed-in node |
| Android foreground service | Keeps the node alive when backgrounded | `specialUse` service (as the Kotlin app; `dataSync` stops after 6 h on Android 15+) with a low-importance notification, started as soon as the node is up so it is running before the app leaves, retried on resume when Android refused it, stopped on stop/sign-out; Settings asks for unrestricted battery | Unverified | `test/background_service_test.dart`; the device check is in `docs/TESTING.md` and has not been run on a phone |
| Android network hooks | ConnectivityManager-backed interfaces and DNS | `PlatformBridge.kt` + JNI (`platform_jni.c`), `"platform": "host"` | Done | Landed in #16; builds in CI, not yet run on a device |
| Android system back | Compose back stack; back on the node list leaves the app | One policy in `lib/src/back.dart`: sheets, dialogs and menus pop, then the tab's page, then the first tab, then a second press to leave | Done | `tool/back_android.sh` in `android-smoke` sends real back keys on an emulator and checks each step, the process and the resumed activity |
| Startup states | Empty lists until the node reports | Nodes, services, agents and logs show a loading state until the node is Running (or failed for good), and a node name resolves through the tsnet peer table, not the system resolver | Done | `tool/agents_android.sh` plus web previews (`?tailnet=starting`, `?herdr=tailnet|connecting|error`); resolution has Go tests |
| Accessibility | Compose semantics | Screen-reader labels, Esc dismissal, reduce motion, text scale clamped to 0.9–1.3 | Done | Landed in #15; screenshots for reduce motion and scale |
| Linux desktop | — | Bundle with both native libraries, run on Xvfb in CI | Done | Added beyond the Kotlin app |
| Windows / macOS | — | Unsigned packages built on a tag or manual run, native DLL/dylib wired | Unverified | Never launched |
| iOS | — | `c-archive` links into the Runner | Unverified | Unsigned package builds; the Runner target force-loads both archives and references `td_start` / `td_term_create`, so a missing archive fails the link. The next macOS CI build has to prove the symbols in the binary |

## Not parity, on purpose

- **Web** is a preview and debug target only; it has no native backend and stays on fixtures.
- **Desktop and iOS** go beyond the Kotlin app, which is Android-only. Their build settings live in
  `.github/workflows/platform-release.yml`.
