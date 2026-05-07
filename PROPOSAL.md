# Proposal: LP-100A Native macOS Client

**Status:** Draft · **Date:** 2026-05-07 · **Owner:** VU3ESV

## 1. Problem

The LP-100A WebSocket server
([VU3ESV/LP-100A-Server](https://github.com/VU3ESV/LP-100A-Server)) ships a
single-page web client embedded in its binary at `/`. It works in any browser
on the LAN, but a browser tab is a poor home for a station instrument:

- Tabs get closed; the operator has to find the right URL and re-open.
- A backgrounded tab sleeps and the connection-state pill goes stale.
- There is no native notification path when the SWR alarm trips. The
  operator has to be looking at the tab to see the red pill blink.
- Browsers do not expose live readouts to the OS chrome — there is no
  always-visible glanceable view of power and SWR while the operator is in
  another app (logging, digital modes, a CW keyer).
- Server URL lives in a bookmark, not in app preferences. Multiple shacks
  / multiple servers means juggling bookmarks.

Operators want a real Mac app that looks and behaves like the web client but
plays nicely with the OS.

## 2. Goals & non-goals

**Goals**

1. **Visual parity** with the server's reference web client: same LCD bezel,
   teal/amber palette, scan-lines, dashed dividers, ui-monospace numerics.
   When a user has both open side-by-side they should look like the same
   instrument.
2. **Functional parity** with the web client's Normal and Vector views and
   the three control verbs (`alarm_step`, `mode_step`, `peak_toggle`).
3. **Functional parity** with the web client's SETUP overlay — mode-cycle
   re-alignment picker, server log-level picker, read-only setup-screen
   reference cards from the LP-100A Quick Start Guide.
4. **First-class macOS integration** that the web client can't offer:
   menu-bar live readout, native notifications on alarm, Cmd+, preferences,
   keyboard shortcuts.
5. **Drop-in client.** No server changes required. Talks the same JSON over
   WebSocket; works against any version of the server that satisfies its
   PROPOSAL.md §4 contract.
6. **Native-feel reliability.** Auto-reconnect on network blips; survives
   the Mac sleeping; no spinning beachballs on the main thread.

**Non-goals (v1)**

- iOS / iPadOS apps. SwiftUI code may port later, but v1 ships macOS only.
- Charting / historical telemetry. Same reasoning as the server's PROPOSAL
  §10 — a separate consumer is the right home for that.
- Multi-server simultaneous monitoring (one window, one meter). Multiple
  windows pointed at different servers is a v2 stretch.
- Re-implementing the server's removed display modes (dBm/RL, Direct Input,
  Peak-to-Avg). The serial protocol can't drive them reliably; we keep the
  server's two-view set.
- Authentication. Like the server, we trust the LAN.
- App Store distribution in v1. Direct download / `notarytool`-stapled DMG
  is enough; revisit if user demand surfaces.

## 3. Architecture

```
┌────────────────────────────────────────────────────────┐
│                  LP-100A-App.app                       │
│                                                        │
│   ┌────────────────────────┐    ┌─────────────────┐    │
│   │   SwiftUI scene tree   │    │   MenuBarExtra  │    │
│   │  (ContentView,         │    │   (live PWR/SWR │    │
│   │   NormalView,          │    │    glance)      │    │
│   │   VectorView,          │    └────────┬────────┘    │
│   │   SetupOverlay,        │             │             │
│   │   KeypadView)          │             │             │
│   └─────────────┬──────────┘             │             │
│                 │                        │             │
│                 ▼                        ▼             │
│   ┌──────────────────────────────────────────────┐     │
│   │   MeterViewModel  (@MainActor, ObservableObject) │ │
│   │   • snapshot: Telemetry?                     │     │
│   │   • connection: .connected/.reconnecting/.disconnected │
│   │   • viewIdx, setupOpen                       │     │
│   │   • peakPwr, peakSwr (sticky-peak decay)     │     │
│   └─────────────────────────┬────────────────────┘     │
│                             │                          │
│   ┌─────────────────────────▼────────────────────┐     │
│   │   WSClient (actor)                           │     │
│   │   • URLSessionWebSocketTask                  │     │
│   │   • exponential backoff: 0.5s → 10s          │     │
│   │   • heartbeat watchdog → connection state    │     │
│   │   • inbound: AsyncStream<ServerFrame>        │     │
│   │   • outbound: send(ClientFrame) async throws │     │
│   └─────────────────────────┬────────────────────┘     │
│                             │                          │
│   ┌─────────────────────────▼────────────────────┐     │
│   │   ConfigClient (actor)                       │     │
│   │   • GET  /api/config                         │     │
│   │   • GET  /api/log-level                      │     │
│   │   • POST /api/log-level                      │     │
│   └──────────────────────────────────────────────┘     │
│                             │                          │
└─────────────────────────────┼──────────────────────────┘
                              │  HTTP + WebSocket
                              ▼
                    ┌──────────────────┐
                    │   LP-100A-Server │
                    │   (the Pi/Mac/PC)│
                    └──────────────────┘
```

**Threading model.** `MeterViewModel` is `@MainActor`-isolated; SwiftUI views
read it directly. `WSClient` and `ConfigClient` are actors below the view
model; they hop to the main actor when delivering frames. Decode happens off
the main thread; UI updates happen on it. There is no shared mutable state
crossing actor boundaries without `await`.

**Why this shape.** The server already does the hard part — single-writer
serial, fan-out, snapshot-on-connect. The client is mostly: render telemetry,
issue three commands, survive network blips. MVVM with one view-model fits
that surface comfortably; anything heavier (Redux-style stores, Combine
graph) is over-built for the size of the state.

## 4. Wire protocol

The app speaks the server's existing protocol verbatim. From the server's
PROPOSAL.md §4:

**Server → app (incoming, parsed by `WSClient`):**

```swift
enum ServerFrame: Decodable {
    case telemetry(seq: Int, ts: String, data: Telemetry)
    case heartbeat(seq: Int, ts: String)
    case status(level: String, msg: String)   // "warn" | "info" | "error"
    case ack(ref: String, ok: Bool, error: String?)
}

struct Telemetry: Decodable, Equatable {
    let powerW: Double      // power_w
    let zOhm: Double        // z_ohm
    let phaseDeg: Double    // phase_deg
    let swr: Double
    let dbm: Double
    let dbw: Double
    let range: Range        // .high | .mid | .low
    let mode: PeakMode      // .average | .peakHold | .tune
    let alarmSetpoint: AlarmSetpoint
    let alarmTripped: Bool
    let callsign: String
}
```

**App → server (outgoing):**

```swift
enum ClientFrame: Encodable {
    case command(id: String, action: Action)  // .alarmStep | .modeStep | .peakToggle
    case resync
}
```

Every command carries a UUID `id`. The view model records `(id → action)`
in a small ring buffer; when the matching `ack` arrives we either clear the
optimistic state or surface the failure (`ack ok:false` with `error`).

The app never sends raw `A`/`M`/`F` bytes — those are the server's private
vocabulary. Same reasoning as the web client: keeps us insulated from any
future meter-firmware change.

## 5. Connection lifecycle

On launch:

1. Read `serverURL` from `UserDefaults` (default `http://localhost:8088`).
   If empty, open the Preferences sheet first.
2. `GET /api/config` → seed `VIEWS` (cycle order) and `allow_control`. If
   `allow_control == false`, render the three keypad buttons disabled with
   a tooltip: "Server is in read-only mode."
3. `GET /api/log-level` → seed the SETUP overlay's log-level picker.
4. Open the WebSocket. Server sends a snapshot immediately on connect; the
   first paint is correct without waiting for the next change.

While running:

- `URLSessionWebSocketTask`'s `receive()` loop runs in `WSClient`. Each
  frame decodes to a `ServerFrame` and is forwarded to `MeterViewModel` on
  the main actor.
- A heartbeat watchdog (Swift `Task` with `Task.sleep`) checks "did we hear
  *anything* in the last 2× heartbeat_ms?" Default 4 s. Miss → connection
  pill goes yellow ("reconnecting…").
- On socket close or watchdog timeout: tear down the task, schedule a
  reconnect with exponential backoff (0.5s, 1s, 2s, 4s, 8s, capped at 10s),
  identical to the web client's policy.
- On reconnect success the server resends a snapshot — the app does not need
  to issue `resync`.

When the app foregrounds after a long sleep (`NSApplicationDidBecomeActive`):
issue `{"type":"resync"}` once, in case heartbeats were missed during sleep
but the WS is technically still open.

## 6. UI design — visual parity

The web client's CSS tokens become a `Tokens.swift` enum. SwiftUI
ViewModifiers reproduce the LCD bezel, the dashed inter-cell dividers, the
glow-on-numerics. Specifically:

| Web element                          | SwiftUI equivalent                                                  |
|--------------------------------------|---------------------------------------------------------------------|
| `.meter` (rounded case + bezel)      | `RoundedRectangle` with linear gradient + `.shadow(radius: 30, y: 10)` |
| `.lcd` (inset CRT-ish surface)       | `RoundedRectangle` filled `Color(0x06080a)` + inner shadow + scan-line `Canvas` overlay at 4% alpha |
| `.track` / `.fill` (bargraphs)       | `GeometryReader` + `Rectangle` for the fill; `.animation(.easeOut(duration: 0.09))` for width |
| `.peak` (sticky peak markers)        | A 2-pt-wide `Rectangle` whose `offset` decays in `MeterViewModel.tick()` (a `Timer.publish` on `RunLoop.main`) |
| `.compass` (polar Z)                 | `Canvas { ctx, size in … }` — draw ring, ticks, labels, needle, dot |
| `.screen-foot` pills                 | `HStack` of `PillView(label:value:)` with the same letter-spacing/uppercase styling |
| `button.key` (Mode/Alarm/Peak)       | `ButtonStyle` with the gradient + bottom-edge shadow + `:active` translateY(1pt) |
| Connection dot                       | `Circle().frame(8×8).shadow(color: green, radius: 4)` |
| SETUP overlay grid                   | `LazyVGrid(columns: [.adaptive(minimum: 280)])` — same scrolling card layout |

**Window.** Default 800×640; min 720×560. Resizable; respects the web
client's `@media (max-width: 540px)` breakpoint by collapsing the
two-column grid into a single column. Title bar uses the brand line
"LP-100A · WebSocket Bridge" the same way the web `.topbar` does.

**Typography.** SF Mono (numerics) + SF Pro (labels, uppercase). The web
client falls back to `ui-monospace, "SF Mono", Menlo, Consolas` — on macOS
we just take SF Mono.

**Animations.** Match the web's timings (90 ms bar fill ease-out, 200 ms
peak marker / needle ease) so they look identical when running side by
side. Use `withAnimation(.linear(duration: 0.09))` etc.

## 7. Mac-specific affordances (the reasons to be native)

1. **Menu-bar live readout.** A `MenuBarExtra` showing
   `1457W · 1.02` updated from the same view-model. The format shortens
   for long values (`1.5kW`); the menu opens a popover with the full
   readout block (PWR, SWR, Range, Mode) and a "Show Window" button.
2. **Native notifications.** When `alarm_tripped` rises edge-low → high,
   post a `UNUserNotificationCenter` notification ("SWR alarm — 2.3 above
   2.0"). User can disable in Preferences. Notifications are throttled —
   one per 30 s of continuous trip, then a single "cleared" notification
   when the alarm releases.
3. **Preferences (Cmd+,).** A standard `Settings` scene with three
   sections: Server (host:port, "Test connection" button), Notifications
   (alarm on/off, sound), Display (always-on-top toggle, menu-bar item
   on/off, light/dark scheme — though the LCD aesthetic only really makes
   sense in dark).
4. **Keyboard shortcuts.**
   - `⌘1` switch to Normal view
   - `⌘2` switch to Vector view
   - `⌘M` Mode (advances cycle + sends `mode_step`)
   - `⌘A` Alarm setpoint step (`alarm_step`)
   - `⌘P` Peak/Avg/Tune toggle (`peak_toggle`)
   - `⌘,` Preferences
   - `⌘R` Resync (force `{"type":"resync"}`)
   - `⌘.` Toggle SETUP overlay
5. **Standard menu bar.** App / File / View / Window / Help. View menu
   exposes the cycle and the SETUP toggle; Help opens the server's
   GitHub README in the default browser.
6. **Sleep/wake hooks.** On wake (`NSWorkspace.didWakeNotification`) we
   `resync` and reset the heartbeat watchdog instead of waiting for the
   next missed heartbeat. Eliminates the "stale yellow pill on lid open"
   that the web client has to live with.
7. **Window state restoration.** Standard NSWindow restoration — frame and
   selected view persist across launches. Same `lp100a.viewIdx` semantics
   as the web client's localStorage, just stored in `UserDefaults`.

## 8. Configuration and persistence

- `UserDefaults` keys (all under suite `com.vu3esv.lp100a-app`):

  | Key                     | Type   | Default                  | Notes                                   |
  |-------------------------|--------|--------------------------|-----------------------------------------|
  | `serverURL`             | String | `http://localhost:8088`  | Edited via Preferences                  |
  | `viewIdx`               | Int    | `0`                      | 0 = first enabled view                  |
  | `meterModeOffset`       | Int    | `0`                      | Re-alignment offset (see below)         |
  | `alarmNotifications`    | Bool   | `true`                   |                                         |
  | `menuBarItemEnabled`    | Bool   | `true`                   |                                         |
  | `alwaysOnTop`           | Bool   | `false`                  |                                         |

- **`meterModeOffset` and SETUP re-alignment.** The web client and this app
  both have to track the meter's Peak/Avg/Tune state by counting `M` presses
  they have sent, because the serial protocol gives no readback. Persisted
  across launches so that the offset survives quitting; reset by the user
  picking the meter's actual mode in the SETUP overlay.

- **Server-side state we touch:** only `/api/log-level` (POST). Everything
  else read-only.

## 9. Failure modes

| Failure                                          | App behavior                                                                  |
|--------------------------------------------------|-------------------------------------------------------------------------------|
| Server unreachable on launch                     | Connection pill red; banner with "Check Preferences" button; auto-retry every 10 s |
| WebSocket drops mid-session                      | Pill yellow → red; exponential backoff reconnect; on success request `resync` |
| Bad JSON frame from server                       | Log via OSLog; ignore the frame; do not disconnect                            |
| `ack ok:false` (e.g. `allow_control = false`)    | Toast "Server rejected: <error>"; revert any optimistic UI state              |
| Server returns `views: []` from `/api/config`    | Fall back to `["normal", "vector"]` (same as the web client)                  |
| Mac sleeps for >2 s (heartbeat watchdog fires)   | Pill yellow on wake; one `resync`; recover within one heartbeat               |
| User closes main window                          | App keeps running if menu-bar item is enabled; otherwise quit (standard Mac)  |

## 10. Distribution and signing

- Build with Xcode, sign with the developer's Apple Developer ID, notarize
  with `xcrun notarytool`. Ship as a stapled `.dmg`.
- No sandbox in v1 — we make outbound network connections to a user-supplied
  host and need network entitlement only. Sandbox is fine to add but should
  not block v1.
- Hardened runtime: yes. No JIT, no DYLD env, no debugger entitlements
  needed.
- App Store: out of scope for v1. Direct-download is the simpler ship.

## 11. Milestones

1. **M1 — wire & data model.** `WireProtocol.swift` with Codable round-trip
   tests against fixture JSON captured from a running server. `WSClient`
   actor with reconnect + heartbeat watchdog. No UI yet — just a
   `print()`-driven smoke test that connects and logs telemetry. Validates
   the protocol contract without UI risk.
2. **M2 — Normal view + connection pill.** Bare window: top bar with the
   pill, `NormalView` rendering PWR (with mode-suffix) and SWR bargraphs +
   numeric readouts + status pills + the three keypad buttons. Hardcode
   server URL. The "two-tab fan-out" demo of the server PROPOSAL §6 should
   work between this app and a browser tab.
3. **M3 — Vector view + view cycle.** `VectorView` with the polar compass
   `Canvas`. Mode button cycles views, stores `viewIdx`, persists in
   `UserDefaults`. Visual review against the web client side by side; tune
   colors / spacing until they match.
4. **M4 — SETUP overlay.** Mode re-alignment picker, server log-level
   picker (`/api/log-level` GET/POST), read-only setup-screen reference
   cards (port the `SETUP_SCREENS` data verbatim from the web).
5. **M5 — Mac integration.** Preferences (Cmd+,), `MenuBarExtra` live
   readout, alarm-trip notifications, keyboard shortcuts, sleep/wake
   hooks. This is the milestone that justifies the existence of a native
   app — push hard on polish here.
6. **M6 — Distribution.** App icon, README with screenshots, signed
   notarized DMG, GitHub release with checksums. Smoke-test on Intel and
   Apple Silicon Macs.

## 12. Open questions

- **Bonjour discovery.** The server doesn't advertise via mDNS today.
  Worth proposing as an upstream change, or stay with manual host:port?
  Recommendation: file an issue on the server repo asking for `_lp100a._tcp.local`
  advertisement; ship v1 with manual host:port.
- **Multiple servers, one app.** v2 if anyone asks. The view model is per-window
  so it's structurally feasible.
- **iPad / iPhone.** SwiftUI views should port; URLSession WebSocket works
  on iOS. The deciding question is whether a phone form factor is worth
  the auxiliary App Store / TestFlight burden. Defer.
- **Charts.** Swift Charts could plot a rolling 60-second power/SWR graph
  cheaply. Out of scope for v1 per the server's non-goals; revisit if
  operators ask.
- **Light mode.** The web client is dark-only and looks intentional.
  Recommendation: ship dark-only and document it. A "light theme" is a
  surprising amount of work for a workshop tool.

## 13. Out of scope, explicitly

- Replacing the server's web client. The web client stays canonical for
  cross-platform / no-install access.
- Logging / charting / alerting beyond a single edge-triggered alarm
  notification. Use a dedicated consumer of `/ws` for that — same advice
  the server gives.
- iOS / iPadOS / Apple TV / Vision Pro. Maybe later.
- Any feature that requires changing the server's wire protocol. If it
  comes up, file an issue upstream first.
