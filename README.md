# LP-100A-App

A native macOS client for the
[LP-100A WebSocket Server](https://github.com/VU3ESV/LP-100A-Server) — the
upstream daemon that owns the serial connection to the Telepost LP-100A RF
Power Meter and exposes telemetry + control over WebSocket. This app is one
of those clients, replicating the look & feel of the server's embedded
reference web UI as a real Mac app.

![LP-100A](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## What it does

- **Live telemetry** from the LP-100A: power, SWR, |Z|, phase, dBm/dBW,
  range, peak/avg/tune mode, alarm setpoint, callsign — pushed over
  WebSocket from the server.
- **Two views** that match the server's reference web client:
  - **Normal** — PWR + SWR bargraphs (with sticky peak markers + range-aware
    ticks) and big numeric readouts.
  - **Vector Z** — |Z|, phase, R, X cells plus a polar compass needle.
- **Three control verbs** (the only ones the LP-100A's serial protocol
  accepts): Mode (cycles peak/avg/tune), Alarm step (cycles SWR setpoint),
  Peak/Avg/Tune toggle.
- **SETUP overlay** — read-only reference cards for all 19 of the meter's
  SETUP screens (LP-100A Quick Start Guide v4.1), plus a mode-cycle
  re-alignment picker and a server log-level picker (`/api/log-level`).

What's added on top of the web client (the reasons to be native):

- **Menu-bar live readout** — glance-able PWR + SWR while the main window
  is hidden.
- **Native macOS notifications** — alert when the SWR alarm trips, throttled
  to one per 30 s.
- **Preferences (⌘,)** — server URL with "Test connection" button, alarm
  notifications toggle, menu-bar item toggle.
- **Keyboard shortcuts** — ⌘1 / ⌘2 view switch, ⌘M / ⌘A / ⌘P controls,
  ⌘. SETUP overlay toggle, ⌘R resync.
- **Sleep/wake hook** — issues a resync on `NSWorkspace.didWakeNotification`
  so the meter is correct the moment the lid opens.

## Install

### From a release DMG

1. Download `LP-100A-App-<version>.dmg` from the
   [Releases](https://github.com/VU3ESV/LP-100A-App/releases) page.
2. Open the DMG, drag **LP-100A.app** to `/Applications`.
3. **Gatekeeper bypass.** This app is ad-hoc-signed, not Apple-notarized
   (yet). Once after install, run:
   ```sh
   xattr -d com.apple.quarantine /Applications/LP-100A.app
   ```
   Then double-click as normal. A future release will be notarized; until
   then, this one-time bypass is the cost of skipping the Apple Developer
   Program fee for v1.

### Configure

On first launch the app expects the server at `http://localhost:8088`.
Open **Preferences (⌘,)** and set the URL to your server's host:port. Hit
**Test connection** to verify, then **Apply**.

## Build from source

Requirements: macOS 13+, Xcode 15+ (or Xcode-CLT with Swift 5.9+).

```sh
git clone https://github.com/VU3ESV/LP-100A-App
cd LP-100A-App

# Run tests
swift test

# Run from Xcode-CLT (debug, single-arch)
swift run

# Build a universal (arm64+x86_64) release .app bundle in dist/
VERSION=$(git describe --tags --always) ./scripts/build-app.sh

# Wrap the .app in a DMG with /Applications symlink
VERSION=$(git describe --tags --always) ./scripts/make-dmg.sh
```

The `.app` is ad-hoc-signed (`codesign --sign -`); fine for local use and
for distribution if users do the `xattr -d` step above. Notarization is a
TODO item.

## How it works

- One `MeterViewModel` (`@MainActor`) owns the latest snapshot, connection
  state, view-cycle index, and SETUP toggle.
- A `WSClient` actor wraps `URLSessionWebSocketTask`, auto-reconnects with
  0.5 → 10 s exponential backoff, and runs a 4 s heartbeat watchdog (no
  inbound frame for >4 s = drop and reconnect).
- A `ConfigClient` actor handles `GET /api/config` (bootstrap) and
  `GET/POST /api/log-level` (SETUP overlay).
- The wire protocol matches the server's PROPOSAL.md §4 verbatim:
  `telemetry` / `heartbeat` / `status` / `ack` server frames, `command` /
  `resync` client frames.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the detailed architecture review.

## Project layout

```
LP-100A-App/
├── README.md                # this file
├── CLAUDE.md                # session orientation
├── PROPOSAL.md              # design proposal
├── ARCHITECTURE.md          # architecture review
├── LICENSE                  # MIT
├── Package.swift            # Swift Package manifest (executable + tests)
├── Sources/LP100AApp/
│   ├── App.swift            # @main, scenes (WindowGroup, Settings, MenuBarExtra)
│   ├── Theme/               # Tokens, LCDStyle (mirrors :root in the web client)
│   ├── Net/                 # WireProtocol, WSClient, ConfigClient
│   ├── ViewModels/          # MeterViewModel
│   ├── Views/               # ContentView, Normal, Vector, Setup, Keypad, Pill, etc.
│   └── MenuBar/             # MenuBarLabel + MenuBarContent popover
├── Tests/LP100AAppTests/    # WireProtocol + scaling round-trips
├── Resources/Info.plist     # bundle template (VERSION substituted at build time)
├── scripts/                 # build-app.sh, make-dmg.sh, make-icon.sh
└── .github/workflows/       # release.yml — builds DMG, attaches to release
```

## Testing without a real meter

The server retries the serial port forever when no meter is attached, and
emits heartbeat-only frames. The app's connection pill will still go green
and the readouts will simply stay at `--`. To exercise the data path
without hardware, point a copy of the server config at a fake serial source
or use the server's `-config` flag to set `port = "/dev/null"` (the server
keeps trying to open it, you keep getting heartbeats).

For unit tests, see `Tests/LP100AAppTests/WireProtocolTests.swift` — JSON
fixtures are inlined.

## Limitations

- **No authentication.** The server is LAN-only by design; this client
  follows suit.
- **Mode tracking is local.** The serial protocol gives no readback of the
  meter's current peak/avg/tune state, so the app counts the `M` presses
  it has sent. After a meter restart, use the SETUP overlay's "Re-align
  web with meter" picker to sync.
- **Two views only.** dBm/RL, Direct Input (Field Strength), and
  Peak-to-Average were dropped from the server because the meter's serial
  Power/dBm fields read 0 / noise floor during TX even when the LCD shows
  real values. We track that decision — Normal and Vector stay accurate.

## Contributing / issues

Open an issue at https://github.com/VU3ESV/LP-100A-App/issues. For
upstream protocol or server questions, file at the
[server repo](https://github.com/VU3ESV/LP-100A-Server) instead.

## License

MIT — see [LICENSE](LICENSE).
