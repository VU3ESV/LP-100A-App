# Changelog

All notable changes to **LP-100A-App** — a native macOS client for the LP-100A digital
vector wattmeter that also ships as an [Amateur Radio Suite](https://github.com/VU3ESV/AmateurRadioSuite)
plugin. Format follows [Keep a Changelog](https://keepachangelog.com/); releases are
auto-cut on merge to `main` (tags `vX.Y.Z`).

## [Unreleased]

### Added
- **Plugin build & release pipeline** ([CONVERTING-A-PLUGIN.md §7](https://github.com/VU3ESV/AmateurRadioSuite/blob/main/docs/CONVERTING-A-PLUGIN.md)):
  CI now builds the `.appex`/`.radioplugin` on every PR, and each release attaches
  `LP-100A-App-<version>.radioplugin` (+ `.sha256`) alongside the `.dmg`.

### Changed
- **Release on merge**: the release workflow was tag-only; it now also **auto-cuts a release
  on every merge to `main`** (auto patch-bump of the latest `vX.Y.Z` tag), matching LP-700
  and the suite. Tag-push and manual dispatch still work.

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
