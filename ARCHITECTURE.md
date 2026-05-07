# Architecture review — LP-100A-App

**Date:** 2026-05-07 · **Status:** v0.1 (initial implementation review)

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

The v0.1 implementation is **shippable** for VU3ESV's own use and for
small-scale community testing. It hits proposal milestones M1 (wire +
data), M2 (Normal + connection pill), M3 (Vector + cycle), M4 (SETUP
overlay), and most of M5 (Mac integration: Cmd+, prefs, MenuBarExtra,
notifications, keyboard shortcuts, sleep/wake hook). M6 (signed +
notarized release) is gated on Apple Developer ID enrollment and is
left as a v0.2 follow-up.

The architecture has no structural surprises and matches the proposal.
The risks listed in §9 are quality-of-life rather than correctness
issues.
