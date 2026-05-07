# LP-100A-App

A native macOS client for the **LP-100A WebSocket Server**
([VU3ESV/LP-100A-Server](https://github.com/VU3ESV/LP-100A-Server)). The server
owns the serial connection to the Telepost LP-100A RF Power Meter and exposes
telemetry + control over a WebSocket; this app is one of those clients,
delivering the same UX as the server's embedded reference web page in a real
Mac window.

## Why a native app?

The server already ships a single-page web UI at `/` (see
`internal/web/static/index.html` in the server repo). It works fine in a
browser tab, but ham-shack operators want:

- A persistent window that survives sleep/wake without a tab refresh.
- Menu-bar live readout of power and SWR while the main window is hidden.
- Native macOS notifications when the SWR alarm trips.
- Cmd+, Preferences for the server URL — no `localStorage` rehearsals.
- Keyboard shortcuts for the three control buttons (Mode / Alarm / Peak).

The native app is **not** a fork of the server's UI — it is a second client
of the same WebSocket. The server stays authoritative.

## Repository layout (proposed)

```
LP-100A-App/
├── CLAUDE.md                    # this file
├── PROPOSAL.md                  # design proposal
├── README.md                    # build / run / install (added once code lands)
├── LP-100A-App.xcodeproj/       # Xcode project (or .xcworkspace if SPM-bundled)
├── LP-100A-App/
│   ├── LP100AApp.swift          # @main App, scene composition
│   ├── ContentView.swift        # the meter face (top-level layout)
│   ├── Theme/
│   │   ├── Tokens.swift         # color/spacing tokens — mirrors the web client's :root vars
│   │   └── LCDStyle.swift       # ViewModifiers for the LCD bezel, scan-lines, dashed borders
│   ├── Views/
│   │   ├── NormalView.swift     # PWR + SWR bargraphs, numeric readouts
│   │   ├── VectorView.swift     # |Z|, phase, R, X, polar compass
│   │   ├── SetupOverlay.swift   # mode-picker + log-level + read-only setup-screen reference
│   │   ├── KeypadView.swift     # the three Mode/Alarm/Peak buttons
│   │   └── StatusBar.swift      # connection-state pill + brand line
│   ├── ViewModels/
│   │   └── MeterViewModel.swift # @MainActor ObservableObject — telemetry, view cycle, commands
│   ├── Net/
│   │   ├── WSClient.swift       # URLSessionWebSocketTask wrapper with auto-reconnect
│   │   ├── WireProtocol.swift   # Codable structs for telemetry / heartbeat / status / ack / command
│   │   └── ConfigClient.swift   # GET /api/config, GET/POST /api/log-level
│   ├── MenuBar/
│   │   └── MenuBarExtra.swift   # NSStatusItem-equivalent live readout
│   └── Resources/
│       └── Assets.xcassets      # AppIcon, accent color
└── LP-100A-AppTests/
    ├── WireProtocolTests.swift  # JSON round-trips against fixtures from the server
    └── ScalingTests.swift       # range → bar % math, |Γ| derivation, etc.
```

The exact directory shape is provisional — settle it when the first code lands.
What is not provisional: keep `Net/WireProtocol.swift` as a thin Codable mirror
of the server's frames, and never let UI code parse JSON directly.

## Stack decisions (proposed — confirm before coding)

- **Language / UI:** Swift 5.9+, **SwiftUI**. SwiftUI handles the LCD aesthetic
  (custom shapes for the bargraph fills, `Canvas` for the polar compass) without
  fighting AppKit, and it gives us `MenuBarExtra` for free on macOS 13+.
- **Minimum target:** macOS 13 Ventura. Drops to 14 only if `MenuBarExtra`
  composition forces it.
- **Architecture:** MVVM. One `@MainActor`-isolated `MeterViewModel` owns the
  latest `Snapshot` plus connection state; views observe it. Network I/O lives
  in actors below the view-model layer.
- **WebSocket:** `URLSessionWebSocketTask` from Foundation. No third-party
  WebSocket library — the server's protocol is plain JSON over WS, and the
  built-in client is enough. Reconnect logic is hand-rolled (see PROPOSAL.md §5).
- **Dependencies:** none in v1. If a charting library is needed later (post-v1),
  prefer Swift Charts (built in on macOS 13+).
- **Build system:** Xcode project. Add SwiftPM later only if a real third-party
  dep arrives. CI builds via `xcodebuild` on a Mac runner.
- **No CocoaPods / Carthage.** Both are dead-weight for a single-binary app.

## What this app talks to

Everything happens through the server's HTTP+WS surface
(documented in the server's CLAUDE.md):

| Path             | Method     | Used for                                             |
|------------------|------------|------------------------------------------------------|
| `/api/config`    | GET        | Bootstrap — reads `views` (cycle order) and `allow_control` flag at launch |
| `/api/log-level` | GET / POST | Setup overlay — read and change the running server's slog level |
| `/ws`            | GET (WS)   | Telemetry stream + control verbs (the main loop)     |
| `/healthz`       | GET        | Optional pre-flight probe before opening the WS      |

Default URL is `http://<host>:8088/`. The Mac app stores the user-configured
host in `UserDefaults` under `serverURL`. Bonjour/mDNS discovery is a stretch
goal — the server does not currently advertise itself, so v1 ships a manual
host:port field in Preferences.

**Frames the app must understand** (from PROPOSAL.md §4 of the server):

- `telemetry` — full snapshot under `data`. Always replaces local state.
- `heartbeat` — keep-alive when nothing has changed for >2s. No state change;
  use to decide the connection-state pill stays green.
- `status` — operational warnings (`"serial reopened after 1.3s gap"` etc.).
  Surface in a non-blocking toast / log.
- `ack` — reply to a command we sent. Match by `ref` to the `id` we generated.

**Frames the app sends:**

- `command` with `action: alarm_step | mode_step | peak_toggle`.
- `resync` on demand (e.g. window regains key focus after a long sleep) to
  request the current snapshot without waiting for the next change.

The app **never** synthesizes telemetry locally. R and X in the Vector view
are derived from `z_ohm` and `phase_deg`; |Γ| is derived from `swr` — those
derivations are display math, not state.

## Visual fidelity to the web client

This is the web client's color palette (from `:root` in `index.html`). The
Mac app's `Theme/Tokens.swift` should expose the same names:

```
--bezel        #1a1d22    --bar          #18d4b3 (teal)
--bezel-edge   #0a0c0e    --bar-glow     rgba(24,212,179,0.4)
--case         #11151a    --peak         #b9fff2
--lcd          #06080a    --power        #ffba2b (amber)
--lcd-border   #2a323c    --green/yel/red 2ecc71 / f1c40f / e74c3c
--grid         #1d2630    --label        #8a96a4
```

Specific behaviors to mirror exactly:

- **Power suffix follows mode:** `w` Average, `W` Peak, `T` Tune (lowercase
  matters — see `POWER_MODE_SUFFIX` in `index.html`).
- **Range scaling:** high=750 W, mid=125 W, low=25 W — these are bargraph
  caps, not server-reported maxes. Tick labels are per-range (`PWR_TICKS`).
- **SWR bar coloring:** teal <1.5, yellow 1.5–2.0, red ≥2.0. Same gradient
  stops as the web (`swr-warn`, `swr-bad`).
- **Sticky peaks:** PWR and SWR peak markers hold for 1.5s, then decay 5%/frame.
- **Compass:** vector tip drawn at `(cos(phase)*norm*ringR, -sin(phase)*norm*ringR)`
  where `norm = min(1, |Z|/100)`. Labels: +R right, −R left, +jX up, −jX down.
- **Mode-cycle re-alignment:** the server has no way to query the meter's
  current peak/avg/tune mode, so the web tracks it by counting `M` presses
  it sent. The Mac app must do the same and expose the same "Re-align web
  with meter" picker in the SETUP overlay.
- **Connection pill:** green=connected, yellow=reconnecting, red=disconnected.
  Driven by WS state + heartbeat watchdog (no heartbeat for 2× heartbeat_ms = red).

What is **not** required to match pixel-for-pixel:

- The CSS scan-line repeating gradient — a subtle SwiftUI overlay is fine.
- Web fonts. Use `ui-monospace` equivalents (SF Mono on macOS) for numerics
  and the system font for labels.

## What this app deliberately does not do

- **Own the serial port.** That's the server's job. The Mac app is one of
  many clients; if the meter is plugged into the Mac directly, run the
  server (it builds for macOS) and point this app at `localhost:8088`.
- **Persist telemetry / charts / logs.** The server's PROPOSAL.md §10 calls
  this out as out-of-scope; ditto here. A separate charting consumer can
  subscribe to `/ws`.
- **Re-implement removed views.** The server's CLAUDE.md "Removed views"
  section explains why dBm/RL, Direct Input, and Peak-to-Avg were dropped:
  the meter's serial Power/dBm fields read 0 / noise floor during TX even
  when the LCD shows real values. We keep Normal and Vector for the same
  reason. If the user enables additional `views` in the server config, the
  app should hide the unsupported ones rather than render broken data.
- **Authenticate.** LAN-only, network-trust deployment per the server's
  non-goals. Document it in the README; don't bake in a login flow.

See [PROPOSAL.md](PROPOSAL.md) for the full design.
