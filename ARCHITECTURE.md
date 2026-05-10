# Architecture review — LP-100A-App

**Date:** 2026-05-10 · **Status:** v0.2.7 (perf pass II — publish-side dedup + 2 Hz + coarsened signature)

## Telemetry coalescing and render budgets

The wire pushes telemetry at the meter's poll cadence (~10 Hz on the
LP-100A's 100 ms poll). A human can't read more than ~5 numbers/second,
so we cap UI-driving work at three layers:

1. **WSClient drops telemetry frames inside the throttle window.** Each
   `URLSessionWebSocketTask.Message` is examined as a string first; if
   its body contains the `"power_w"` marker (unique to telemetry frames;
   heartbeat / status / ack don't carry it) AND
   `Date().timeIntervalSince(lastTelemetryDecodedAt) < 0.2`, the actor
   returns without invoking `JSONDecoder`. Result: at sustained TX, ~5×
   fewer JSON decodes — the substring scan is cheap, the JSON parse is
   not.

2. **MeterViewModel coalesces `@Published var snapshot` to ≤2 Hz, with
   publish-side display dedup.** Inbound telemetry events update a
   private `pendingSnapshot`; a single trailing `publishTask` commits
   the latest pending value to `snapshot` after the 500 ms window.
   `handleAlarmEdge` runs on every inbound frame so notifications stay
   timely; only the SwiftUI mutation path is throttled. `stop()`
   cancels the publish task and clears `pendingSnapshot` on disconnect.

   At commit time, the candidate snapshot is reduced to a
   `PublishSignature` (Equatable struct of the formatted strings the
   view will display + 1 %-quantized bargraph buckets). If the
   signature equals the last published one, the `@Published`
   mutation is **skipped entirely** — SwiftUI never gets invalidated
   for noise-floor wobble that rounds to the same on-screen text.
   When the user is transmitting and values genuinely move, dedup
   passes through; when the meter is idling at noise floor, body
   re-evals can drop to ≈0/sec. This is the dominant win — Equatable
   leaves below this layer can short-circuit, but they still cost a
   model construction + tree comparison; the publish-side dedup
   never even allocates a SwiftUI invalidation.

   The dBW / dBm / |Z| / phase fields in `NormalView` and the
   signature both quantize to whole-unit precision. Wire values still
   carry 0.1 — it's just not displayed. At noise floor (Z bouncing
   47.7 ↔ 48.0, phase 80.2 ↔ 80.5) the rounded strings settle on a
   single value, letting the signature stabilise. Power and SWR keep
   `%.1f` / `%.2f` since those are the headline readouts.

   Inverse knob: drop `MeterViewModel.publishInterval` to `0.2` (5 Hz)
   if smoother bargraph motion is wanted during sustained TX. The
   2 Hz default trades fluency for ~5× lower idle CPU.

3. **Value-typed view subtree + layered Equatable.** `ContentView`
   builds a `NormalModel` (Equatable struct: pre-formatted strings,
   pre-quantized bar fractions) on each body evaluation, and passes
   it into `NormalView`. The raw `Telemetry` is deliberately *not*
   in the model — including it would invalidate Equatable on every
   wire-level field jitter. `NormalView` is `Equatable` over the
   model; inside it, the leaf `ReadingCard`s are also `Equatable` and
   `.equatable()`-wrapped so an unchanged Power card skips body +
   layout even when the SWR card moved.

   Toolbar items (`ConnectionBadge`) are likewise `Equatable` and
   `.equatable()`-wrapped at the call site. SwiftUI's bridge to
   AppKit was relayouting toolbar items on every ContentView body
   re-eval despite their inputs being unchanged.

   The bar fraction is quantized to 1 % steps in
   `NormalModel.make` — finer movement isn't visible on a 6 pt
   Capsule bar, and step-quantising is what lets the surrounding
   `Equatable` short-circuit when adjacent samples land in the same
   step.

   The `.animation(value: fraction)` modifier on `PowerBar` is
   intentionally absent. Implicit animations run a 60 Hz CoreAnimation
   transaction until they settle, and at the 5 Hz mutation rate they
   never settle — keeping `NSPerformVisuallyAtomicChange` constantly
   busy. Removing it (combined with the quantized fraction) lets
   `Equatable` actually short-circuit re-renders.

**Empirical:** measured by `ps -o %cpu` over 20 × 1 s windows against
a real `192.168.86.43:8088` server with the meter idling at noise
floor (~10 frames/sec on the wire, Z bouncing 47.7–48.0 Ω, phase
79.5–80.5°, no TX):

| Version | Idle CPU (mean) | Notes |
|---|---|---|
| v0.2.5 | ~9.9 % | Baseline. |
| v0.2.6 | ~9.8 % | First perf pass (5 Hz throttle + Equatable subtree). The earlier "0 %" reading was a `top -l 10 -s 1` sampling artifact — formatted `%.1f` strings still changed ~50 % of frames so layout cost dominated. |
| v0.2.7 | **0.82 %** (median 0.30 %) | Publish-side display dedup + 2 Hz coalesce + whole-unit signature for Z / phase / dBW / dBm. SwiftUI body never gets invalidated for telemetry that rounds to the same on-screen display. |

The dominant win is the publish-side dedup combined with coarser
quantization on the noise-prone fields: SwiftUI never sees a body
invalidation for telemetry that rounds to the same on-screen
display, so the toolbar + meter-face + keypad + menu-bar-label
layout walk doesn't run at idle. Single-digit % spikes still occur
when a value crosses a bucket boundary (one layout pass), but the
window between them lengthens to several seconds.

The original v0.2.6 layer 3 (value-typed `NormalModel` +
`Equatable.equatable()` on `NormalView`, `ReadingCard`, `PowerBar`,
`ConnectionBadge`) is still in place — it's a defence-in-depth that
short-circuits any leaf re-render the source-level dedup didn't
already prevent (e.g. on the first frame of a new TX or when a
bucket boundary is crossed but only one of the two cards moved).

## Changes since v0.2 baseline

The v0.2.x series successively tightens the visual chrome to match
[VU3ESV/LP-700-App](https://github.com/VU3ESV/LP-700-App) so the two
clients read as the same product family on the same desk:

- **v0.2.1** — perceived-latency fix. Dropped the bargraph's 90 ms
  `.linear` fill animation and the 200 ms peak-marker easeOut (visible
  lag against the snapshot). Reused JSONDecoder/JSONEncoder. Defer
  `.connected` until first inbound frame. Decay loop 16 fps → 5 fps.
- **v0.2.2** — adopt LP-700-App's compact native shell. Window 820×440
  default (was min 720×540). Panel padding 10 pt (was 20 pt). Bargraphs
  rebuilt as `ReadingCard` — 40 pt rounded numeric + 6 pt Capsule bar +
  scale tick. Keypad shrunk to `.bordered .controlSize(.small)`.
  Status row collapsed into a `CompactPanel`.
- **v0.2.3** — toolbar pill chrome. Replaced the wide segmented Picker
  in `.principal` with two capsule chips (`cornerRadius 999`,
  accent-tinted border + 12 % accent fill when active). Mirrors
  LP-700's `BackendBadge` styling exactly.
- **v0.2.4** — panel-stack rhythm. Removed the inner `CompactPanel`
  around the dBW/dBm/|Z|/Phase/Peak row so the meter face shows two
  rounded panels stacked (main Panel + bottom CompactPanel) instead of
  three. Restored the `Divider()` after PanelHeader and bumped inner
  spacing 8 → 10 pt to match LP-700 verbatim.
- **v0.2.5** — screenshot launch flags + docs refresh.
- **v0.2.6** — first profile-driven CPU pass. Mirrors LP-700-App's
  c52fe11 + bec7c74 commits: WSClient throttles telemetry decode to
  5 Hz, MeterViewModel coalesces publishes to 5 Hz, `NormalView`
  factored onto a value-typed `NormalModel` with Equatable cards.
  Initial measurement showed 0 % CPU (a `top -l 10 -s 1` sampling
  artifact) but the real cost was still ~9.8 % because formatted
  `%.1f` strings still changed ~half the frames at noise-floor
  wobble — Equatable couldn't short-circuit and layout still ran at
  ~2.5 Hz on the full toolbar + meter + keypad tree.
- **v0.2.7** — second profile-driven CPU pass. Idle CPU dropped from
  ~9.8 % to mean **0.82 % / median 0.30 %**. Three additive
  refinements on top of v0.2.6:
    1. **Publish-side display signature dedup** in
       `MeterViewModel.commitPending`. A `PublishSignature` Equatable
       struct mirrors the formatted strings + 1 %-bar-bucket the
       view will produce; the `@Published` snapshot mutation is
       skipped entirely if the signature matches the last published
       one. SwiftUI never gets a body invalidation for noise-floor
       wobble that rounds to the same on-screen display.
    2. **Coarsened display precision** for noise-prone fields.
       dBW / dBm / |Z| / phase round to whole units in both the
       view (`NormalView`) and the signature, so noise-floor jitter
       (Z 47.7 ↔ 48.0, phase 79.5 ↔ 80.5) settles on a single value
       and lets the dedup catch it. Power and SWR keep `%.1f` /
       `%.2f` since those are the headline readouts.
    3. **2 Hz publish rate** (`publishInterval: 0.5`, was 0.2). Caps
       the layout pass cadence even when values do change. WSClient
       `telemetryMinInterval` matched (0.5) — no point decoding
       faster than the view-model can publish. Inverse knob:
       drop to 0.2 (5 Hz) for smoother bargraph motion if needed.

       See [§ Telemetry coalescing](#telemetry-coalescing-and-render-budgets)
       for the full picture.

## Changes since v0.1

- **Native Mac chrome.** `LCDSurface` / `MeterCase` (custom dark gradient
  panels with scan-lines) were removed. The window now uses an `NSToolbar`
  via `.toolbar` modifier with a connection badge on the leading side, a
  segmented Normal/Vector picker in the principal slot, and shield/wrench
  gear buttons trailing. The body is two `regularMaterial`-backed `Panel`
  surfaces — one for the active view, one for status + keypad. Background
  uses `Color(NSColor.windowBackgroundColor)` so the window adopts the
  system's light/dark appearance.
- **First-launch Connect sheet.** When `UserDefaults["serverURL"]` is
  empty, the app opens a modal `ConnectionSheet` (URL field + inline
  `/healthz` probe + Connect / Cancel-or-Quit footer). Re-openable via
  ⌘K or the toolbar's shield icon. A `ConnectionPlaceholder` view appears
  in the main pane until the user has configured a URL.
- **Explicit connection lifecycle.** `MeterViewModel` gained
  `disconnect()`, `testConnection(urlString:)`, `connectionSheetOpen`,
  `serverURLString`, `hasConfiguredServer`. The main window's status pill
  was removed — connection state lives in the toolbar badge.
- **Native button styles.** `KeypadView` rebuilt on `.bordered` /
  `.controlSize(.large)` with SF Symbol leading icons. The custom
  `KeyButtonStyle` gradient is gone. SETUP overlay's `mode-picker`
  buttons became `.bordered` chips tinted by `.accentColor`.
- **Bargraphs kept the teal/yellow/red fill colors** (functional signal
  severity at a glance) but the track now uses `Color.secondary.opacity(0.12)`
  so it works in both modes.
- **Preferences sheet** rebuilt: Server tab shows a labeled-content
  status row + Change/Reconnect/Disconnect buttons that punt URL editing
  to the Connect sheet (single source of truth for setting the URL).

This document is a focused review of the v0.1 implementation of the
LP-100A-App macOS client. It covers structure, threading, network
behavior, error paths, and known risks. Read alongside
[PROPOSAL.md](PROPOSAL.md) (the design intent) and
[CLAUDE.md](CLAUDE.md) (orientation for contributors).

## 1. Layered structure

The app is four layers, top to bottom:

```
┌────────────────────────────────────────────────────────────────┐
│  Scenes / Views (SwiftUI)                                      │
│    ContentView, NormalView, VectorView, SetupOverlay,          │
│    KeypadView, PreferencesView, MenuBarContent                 │
│    — read-only consumers of MeterViewModel                     │
└──────────────────────────────┬─────────────────────────────────┘
                               │ ObservableObject (Published)
┌──────────────────────────────▼─────────────────────────────────┐
│  ViewModel layer (@MainActor)                                  │
│    MeterViewModel — single source of truth for UI:             │
│      snapshot, connection, viewIdx, setupOpen, peaks,          │
│      log-level, allowControl                                   │
│    Owns the alarm-edge detector, sticky-peak decay loop,       │
│    and command issuance.                                       │
└──────────────────────────────┬─────────────────────────────────┘
                               │ async / event stream
┌──────────────────────────────▼─────────────────────────────────┐
│  Network actors                                                │
│    WSClient (actor) — URLSessionWebSocketTask wrapper.         │
│      Reconnect 0.5→10s backoff. 4s heartbeat watchdog.         │
│      Yields events on a nonisolated AsyncStream.               │
│    ConfigClient (actor) — REST helpers (/api/config,           │
│      /api/log-level GET/POST).                                 │
└──────────────────────────────┬─────────────────────────────────┘
                               │ JSON over WS / HTTP
┌──────────────────────────────▼─────────────────────────────────┐
│  Wire protocol (Codable structs)                               │
│    Telemetry, ServerFrame, ClientFrame                         │
│    — thin mirror of server PROPOSAL.md §4                      │
└────────────────────────────────────────────────────────────────┘
```

**Why this shape.** The server already does the hard part — single-writer
serial, fan-out, snapshot-on-connect. The client's job is mostly: render
telemetry, issue three commands, survive network blips. MVVM with one
view-model fits that surface; anything heavier (Redux store, Combine
graph) would be over-built.

## 2. Concurrency model

| Component        | Isolation        | Notes                                                          |
|------------------|------------------|----------------------------------------------------------------|
| `MeterViewModel` | `@MainActor`     | All `@Published` state is main-actor isolated. SwiftUI reads directly. |
| `WSClient`       | `actor`          | Owns the `URLSessionWebSocketTask`, backoff state, watchdog.   |
| `ConfigClient`   | `actor`          | Stateless except for `baseURL`; one `URLSession` shared.        |
| `AsyncStream<Event>` | `nonisolated let` on the actor | Emitted from inside the actor via a single `Continuation`. Consumers iterate from any context. |

Boundary rules:

- The `ws.events` stream is `nonisolated`, so the view-model's listen
  task can iterate it without `await` on each step. The continuation is
  fed only from inside the actor's `emit(_:)` method — single producer.
- Frames cross from the WS actor to `MeterViewModel` via `await self.handle(event:)`,
  hopping to the main actor exactly once per frame.
- Commands flow the other way: `MeterViewModel.send*()` (main actor)
  schedules a `Task { try? await ws?.send(frame) }`. `send` on `URLSessionWebSocketTask`
  is itself thread-safe; the actor wraps it for ergonomics.
- The decay loop in `MeterViewModel.startDecayLoop()` runs in a detached
  Task, sleeping 60 ms between ticks and hopping to the main actor for
  state mutation.

**Risks called out:**

- The decay loop is approx. 16 fps via `Task.sleep(60ms)`. Fine for a
  ham-shack tool but noisy in trace logs. If we ever need it to coalesce
  with display refresh, switch to a `CADisplayLink`-equivalent (no native
  SwiftUI binding, would need an `NSView`-host shim).
- The watchdog wakes once per second and walks `lastFrameAt`. Cheap
  enough; no concern.
- Single `WSClient` instance per app. No multi-server fan-in (planned v2).

## 3. Connection lifecycle

```
                       ┌─────────────┐
                       │ disconnected│  (initial / after error)
                       └──────┬──────┘
                              │ start() / setBaseURL()
                       ┌──────▼──────┐
                       │ reconnecting│
                       └──────┬──────┘
                              │ WS handshake OK
                              │ + lastFrameAt = now
                       ┌──────▼──────┐
       heartbeat       │  connected  │  ◄── frames reset lastFrameAt
       watchdog        └──┬──────────┘
       fires (>4s)       │             ↑
       OR socket close   │             │
                         ▼             │
                  handleDisconnect ────┘ via reconnect with backoff
                  (backoff 0.5→10s)
```

The state-machine is small and sufficient. Specifics:

- **Snapshot-on-connect** is the server's contract — the moment the WS
  handshake completes, the server sends a `telemetry` frame. We don't
  need to issue `resync` to seed the view; UI fills in within ~one
  poll cycle.
- **Heartbeat watchdog** fires from `Task.sleep(1s)` loop, not a
  high-resolution timer, to keep wakeups cheap. 4 s timeout is 2× the
  server's default heartbeat_ms (2000); this matches the web client's
  behavior.
- **Backoff** is 0.5, 1, 2, 4, 8, 10, 10, 10… seconds. Reset to 0.5 on a
  successful connect.
- **Sleep/wake.** `NSWorkspace.didWakeNotification` triggers a full
  `reconnect(serverURL:)` rather than just an inline `resync`. Slightly
  heavier than the proposal's wording but empirically more reliable when
  the lid was closed long enough that the OS already invalidated the WS.
- **App became active** triggers `vm.resync()`, which is cheap.

## 4. UI model

- `ContentView` composes the static frame: top status bar, MeterCase →
  LCDSurface → (active view + screen-foot pills) + KeypadView.
- `NormalView` and `VectorView` each render a snapshot dictionary and
  derived values — they hold no state of their own.
- `SetupOverlay` is rendered into the same LCD area when `vm.setupOpen`
  is true, replacing the active view. Same compositional choice as the
  web client (which switches `.view.active`).
- `KeypadView` reads `vm.connection`, `vm.allowControl`, `vm.setupOpen`
  to compute the disabled state. Click handlers call `vm.sendMode()`
  etc. and rely on the view-model's optimistic-then-confirm semantics.
- `PillView` is the screen-foot label·value primitive. One variant
  (`onTap` non-nil) is clickable and toggles the SETUP overlay.
- `MenuBarLabel` + `MenuBarContent` composes the `MenuBarExtra`. The
  label is a 14-char-ish string; clicking opens a popover with the full
  readout block plus "Show Window" and "Quit".

**Visual fidelity notes:**

- The `:root` palette from the web client is replicated 1:1 in
  `Theme/Tokens.swift`. Hex values match exactly.
- `LCDSurface` has a teal inner-glow shadow + scan-line overlay (`Canvas`
  drawing 1-pt stripes every 3 pt at 1.2 % alpha) — reproduces the web
  client's `::before` `repeating-linear-gradient`.
- Bargraph fills use the same three-stop gradients (teal default, yellow
  warn, red bad) and the same SWR thresholds (1.5 / 2.0).
- Sticky-peak markers decay 5 %/frame after 1.5 s of no new max, same as
  the web client's `tick()` rAF loop.
- Polar compass uses `Canvas` to draw ring + axes + needle + dot. The
  needle math `(cos(phase), -sin(phase)) × min(1, |Z|/100) × ringR` is
  identical to the web's `vec-needle` style transform.

## 5. State persistence

`UserDefaults` (suite: `com.vu3esv.lp100a-app`):

| Key                  | Type | Default                    |
|----------------------|------|----------------------------|
| `serverURL`          | String | `http://localhost:8088`   |
| `alarmNotifications` | Bool   | `true`                    |
| `menuBarItemEnabled` | Bool   | `true`                    |

Not yet wired (planned for follow-up):

- `viewIdx` — currently in-memory only; would survive app restart.
- `meterModeOffset` — re-alignment offset is in-memory only; user has to
  re-align after every restart. The web client persists via localStorage;
  we should match.
- `alwaysOnTop` window option mentioned in PROPOSAL §7 isn't implemented
  yet.

## 6. Error paths

| Failure                                          | Current behavior                                                                            | Risk |
|--------------------------------------------------|---------------------------------------------------------------------------------------------|------|
| Server unreachable on launch                     | `WSClient` enters `reconnecting`; UI pill yellow; backoff retries forever                   | Low — user can open Preferences and fix URL |
| `/api/config` fetch fails                        | Falls back to `["normal", "vector"]` and `allowControl = true` (best-effort, log only)      | Low |
| `/api/log-level` fetch fails                     | Picker shows last-known value (initial `"error"`); POST is fire-and-forget                  | Low |
| WS drops mid-session                             | `handleDisconnect` → backoff reconnect; UI pill yellow then red briefly                     | Low |
| Bad JSON frame                                   | `JSONDecoder` throws; emit `parseError`; OSLog warning; no disconnect                       | Low |
| `ack ok:false`                                   | Status banner shown; banner auto-dismisses after 5 s                                        | Med — banner doesn't tie back to the issuing button (no per-button feedback) |
| Mac sleeps for >2 s                              | Watchdog fires on wake → reconnect; or `NSWorkspace.didWakeNotification` triggers reconnect explicitly | Low |
| `command` sent while `allowControl: false`       | View-model gates client-side; server would NACK if we tried, but we don't issue             | Low |
| Server restart (log-level resets)                | Picker shows the last value we saw, not the new server-side default. Refreshes when SETUP overlay re-opens | Med — picker is briefly stale; user re-opens SETUP to refresh |
| Two `mode_step` clicks in fast succession        | Both queued; view-model bumps `viewIdx` twice optimistically. If server NACKs one, the views could drift | Med — proposal §11 M3 acknowledges this; not addressed in v0.1 |

## 7. Tests

`swift test` runs 13 tests across two suites:

- **WireProtocolTests (7)** — telemetry/heartbeat/status/ack frames decode
  correctly; command/resync frames encode to the exact expected bytes;
  unknown frame types degrade gracefully (no throw).
- **ScalingTests (6)** — power range caps and tick labels match the web
  client; lower-case `w` for Average mode is preserved (LCD convention);
  |Γ| derivation, R/X derivation, SWR-bar fraction edges.

Not yet covered:

- `WSClient` reconnect/backoff behavior. Hard to test deterministically
  without a fake `URLSessionWebSocketTask`. Acceptable gap for v0.1.
- `MeterViewModel` peak decay loop. Time-dependent; could be tested with
  a clock abstraction in v0.2.
- UI snapshot tests. Out of scope; visual review against the web client.

## 8. Build & ship

- **Universal binary** (arm64 + x86_64) via `swift build -c release --arch arm64 --arch x86_64`.
- **App bundle** assembled by `scripts/build-app.sh`:
  copies the binary to `Contents/MacOS/`, expands `Resources/Info.plist`
  template (substitutes `__VERSION__`), generates an `AppIcon.icns` from
  a placeholder PNG, ad-hoc signs (`codesign --sign -`).
- **DMG** built by `scripts/make-dmg.sh`: copies the `.app` plus a
  `/Applications` symlink to a staging dir, runs `hdiutil create ... -format UDZO`.
- **Distribution**: ad-hoc-signed only. Users do `xattr -d com.apple.quarantine`
  once after install. Notarization is a TODO (requires Apple Developer
  Program enrollment).

CI (`.github/workflows/release.yml`):

- Triggers on tag `v*` push.
- Runs on `macos-14` (Sonoma + Xcode 15.x).
- Steps: checkout → swift test → build app → make DMG → upload as
  release asset.

## 9. Risks & follow-ups

**Known issues (v0.1 -> v0.2):**

1. **Persistence gap** — `viewIdx` and `meterModeOffset` are not in
   `UserDefaults` yet. Web client persists; we should match.
2. **Mode-cycle drift on rapid clicks** — back-to-back ⌘M presses bump
   `viewIdx` optimistically without confirming the server processed each
   one. If `allow_control = false` we never issue, so it's a moot point;
   if we issue and it's NACKed, view drifts. Add per-command rollback.
3. **Banner UX** — `statusBanner` is global; doesn't pin to the offending
   button. Cheap polish: tint the button red briefly.
4. **No always-on-top window option** despite mention in PROPOSAL §7.
5. **No per-server profile** — single server URL in UserDefaults.
   Multi-shack users currently re-edit Preferences when they move.
6. **No notarization** — first release is ad-hoc-signed; Gatekeeper
   bypass documented in README. Sign + notarize when Developer ID is
   available.

**Not at risk:**

- Wire protocol stability — frames are 1:1 with the server's
  PROPOSAL.md §4 contract; covered by tests.
- Reconnect correctness — verified manually with `kill -STOP` /
  `kill -CONT` on a local server, and by physically pulling the LAN.
- Memory growth — no caches, no buffers; `lastData` is a single struct
  replaced per frame.

## 10. Verdict

The v0.2 implementation is **shippable** for VU3ESV's own use and for
small-scale community testing. It hits proposal milestones M1–M5 (wire +
data, Normal + connection state, Vector + cycle, SETUP overlay, Mac
integration: Cmd+, prefs, MenuBarExtra, notifications, keyboard
shortcuts, sleep/wake hook), and adds a first-launch Connect sheet plus
a native NSToolbar that wasn't in the original proposal — those came
from real-world feedback that the LCD-replica window without an obvious
"Connect" affordance felt incomplete on macOS.

M6 (signed + notarized release) is still gated on Apple Developer ID
enrollment and remains the v0.3 follow-up.

The architecture has no structural surprises and matches the proposal.
The risks listed in §9 are quality-of-life rather than correctness
issues.
