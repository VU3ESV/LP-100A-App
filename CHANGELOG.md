# Changelog

All notable changes to **LP-100A-App** — a native macOS client for the LP-100A digital
vector wattmeter that also ships as an [Amateur Radio Suite](https://github.com/VU3ESV/AmateurRadioSuite)
plugin. Format follows [Keep a Changelog](https://keepachangelog.com/); releases are
auto-cut on merge to `main` (tags `vX.Y.Z`).

## [Unreleased]

### Fixed
- **Proxy login: a pasted password no longer keeps its trailing line break.** Save now drops
  leading/trailing newlines and refuses other control characters. Before, a copy from a terminal
  stored a wrong password in the shared `ShackProxy` Keychain item and every app got
  "Proxy login rejected".


### Added
- **Connect through an authenticating TLS proxy.** Point the app at the proxy's `https://`
  URL (e.g. `https://192.168.86.43:8088`; `wss://…/ws` is derived) and save a **Proxy login**
  in the Connect sheet. The login lives in the login Keychain (generic password, service
  `ShackProxy`, account = username) and is sent as `Authorization: Basic` on the WebSocket
  upgrade and every HTTP call, **only over `https`/`wss`, never over plain `http`/`ws`**.
  A 401 shows "Proxy login required" (nothing sent) or "Proxy login rejected" (refused) and
  retries at the slow 10 s backoff. The app relies on system trust for the proxy's
  certificate (no pinning) and sends no `Origin` header.
- **Plugin build & release pipeline** ([CONVERTING-A-PLUGIN.md §7](https://github.com/VU3ESV/AmateurRadioSuite/blob/main/docs/CONVERTING-A-PLUGIN.md)):
  CI now builds the `.appex`/`.radioplugin` on every PR, and each release attaches
  `LP-100A-App-<version>.radioplugin` (+ `.sha256`) alongside the `.dmg`.

### Changed
- **Release on merge**: the release workflow was tag-only; it now also **auto-cuts a release
  on every merge to `main`** (auto patch-bump of the latest `vX.Y.Z` tag), matching LP-700
  and the suite. Tag-push and manual dispatch still work.
- **The plugin reports the app's release version.** The `.appex`'s `CFBundleShortVersionString` /
  `CFBundleVersion` and `plugin.json`'s `version` were fixed at 1.0 / 1.0.0 while the app shipped
  as 0.2.x. Both are now stamped with the release `VERSION` by `scripts/make-radioplugin.sh` and
  `scripts/package-signed.sh`, so the Suite's plugin manager, `pluginkit` and System Settings show
  the same version as the app. Suite catalog note: the LP-100A entry's `latestVersion` (1.0.0) has
  to move to the app's scheme, or the Suite will keep reporting an update as available. Ported from
  LP-700-App ([#22](https://github.com/VU3ESV/LP-700-App/pull/22)).

### Fixed
- **Hosted plugin connects on its own.** Loaded in the Amateur Radio Suite (the `.appex`),
  LP-100A now connects to the saved server as soon as it appears and opens the Connect sheet
  only when no server has been configured yet. Previously it sat disconnected until the
  operator opened the connection settings and pressed Connect on every launch. The standalone
  window, the in-process plugin and the hosted extension now share one
  `MeterViewModel.configuredServerURL` rule for "is a server configured". The hosted
  extension keeps its URL in its own sandboxed defaults, so the Suite asks once even when the
  standalone app is already set up. While hosted, the Connect sheet no longer offers **Quit**
  (it would have terminated the Suite or the extension process), and a connect attempt that is
  superseded while the saved server is unreachable no longer hijacks the newer connection.
  Ported from LP-700-App ([#21](https://github.com/VU3ESV/LP-700-App/pull/21)).
- **Auto-reconnect actually reconnects.** `WSClient`'s disconnect handler cancelled the task it
  was running on before sleeping, so after a dropped connection, a server restart, or a launch
  before the server was up no retry ever happened: the app showed Offline until the operator
  reconnected by hand. Retries now run on their own task with the intended 0.5–10 s backoff,
  the badge says Reconnecting (not Offline) while a retry is pending, and the backoff resets
  on the first frame rather than on every attempt. `stop()` is final: a socket it cancelled, or
  one a reconnect replaced, can no longer schedule a retry of its own. Regression tests connect
  to a closed port and expect a second attempt, expect no retry after `stop()`, and expect no
  retry when `stop()` lands while a handshake is still pending.

## [0.2.8] — 2026-06-02
### Added
- **Out-of-process plugin** ([#3](https://github.com/VU3ESV/LP-100A-App/pull/3)): an
  ExtensionKit `.appex` target + `scripts/make-radioplugin.sh` packaging `LP100A.radioplugin`,
  so the suite can browse/install LP-100A and host it sandboxed via `EXHostViewController`.
  Adds a public `LP100AExtension.rootView()` factory; standalone app and in-process plugin
  unchanged.
### Changed
- **RadioPluginKit 1.2 manifest** ([#2](https://github.com/VU3ESV/LP-100A-App/pull/2)):
  adopted the typed manifest/capabilities, synced with the suite contract.

## [0.2.7] — 2026-05-31
### Added
- **Plugin architecture** ([#1](https://github.com/VU3ESV/LP-100A-App/pull/1)): a `public
  LP100APlugin` adapter conforming to `RadioPlugin` lets the Amateur Radio Suite host LP-100A
  in-process; all views/view-models/networking stay `internal`. Per-plugin `UserDefaults`
  via `host.defaults(for:)`.
### Fixed
- Restore the main window after it's closed, via the menu-bar item.
### Performance
- Profile-driven CPU pass II: publish de-dup + 2 Hz refresh + coarsened telemetry signature.

## [0.2.6] — 2026-05-09
### Performance
- Profile-driven CPU pass: idle CPU ~9.9 % → ~0 %.

## [0.2.2] – [0.2.5] — 2026-05-09
### Changed
- Align look-and-feel with LP-700-App: toolbar pill chrome, panel-stack rhythm, regenerated
  screenshots and docs.

## [0.2.1] — 2026-05-08
### Fixed
- Reduced perceived telemetry lag.

## [0.2.0] — 2026-05-08
### Added
- Native macOS shell with a Connect sheet; user manual, screenshots, and a screenshot helper.

## [0.1.0] — 2026-05-07
### Added
- Initial LP-100A-App scaffold.
