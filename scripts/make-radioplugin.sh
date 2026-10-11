#!/bin/bash
# Build LP100AExtension.appex and package it as `LP100A.radioplugin` -- the installable
# bundle the Amateur Radio Suite browses + installs (zip of plugin.json + the .appex).
#
#   VERSION=0.2.10 ./scripts/make-radioplugin.sh   # -> dist/LP100A.radioplugin (+ its sha256)
#
# VERSION (default 0.0.0-dev) is stamped into both places the plugin reports a version, so
# the plugin always carries the same version as the app release it ships with:
#   - the .appex Info.plist (CFBundleShortVersionString / CFBundleVersion, through the
#     MARKETING_VERSION / CURRENT_PROJECT_VERSION build settings) -- what `pluginkit` and
#     System Settings > Extensions show;
#   - plugin.json's "version" (the __VERSION__ placeholder) -- what the Suite's plugin
#     manager shows and compares against its catalog's latestVersion.
#
# Running the installed plugin needs Developer-ID signing + extension approval; this
# produces an ad-hoc-signed package suitable for the catalog/discovery flow and testing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
XCODE_DIR="Xcode"
PROJECT="$XCODE_DIR/LP100APlugin.xcodeproj"
SCHEME="LP100AExtension"
DIST="dist"
PKG="$DIST/LP100A.radioplugin"

# SwiftPM's bare-repo cache trips `safe.bareRepository=explicit` (a common global git
# setting) under xcodebuild; allow it for child git processes without touching config.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

echo "==> Generating Xcode project from project.yml"
( cd "$XCODE_DIR" && xcodegen generate )

echo "==> Building $SCHEME (.appex) -- version $VERSION"
DERIVED="$(mktemp -d)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APPEX="$(/usr/bin/find "$DERIVED/Build/Products" -name 'LP100AExtension.appex' -maxdepth 3 | head -1)"
[ -n "$APPEX" ] || { echo "ERROR: LP100AExtension.appex not found"; exit 1; }

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APPEX/Contents/Info.plist")"
[ "$BUILT_VERSION" = "$VERSION" ] || {
  echo "ERROR: .appex reports version '$BUILT_VERSION', expected '$VERSION'"; exit 1; }

echo "==> Assembling $PKG"
STAGE="$(mktemp -d)"
# Stamp the manifest with the same version as the app and the .appex.
sed "s/__VERSION__/${VERSION}/g" "Xcode/Extension/plugin.json" > "$STAGE/plugin.json"
grep -q "\"version\": \"${VERSION}\"" "$STAGE/plugin.json" || {
  echo "ERROR: plugin.json version was not stamped (is the __VERSION__ placeholder intact?)"; exit 1; }
cp -R "$APPEX" "$STAGE/"

# Only manage our own package — do NOT wipe $DIST, which in a release pipeline also
# holds the standalone .app/.dmg built by build-app.sh / make-dmg.sh.
mkdir -p "$DIST"
rm -f "$PKG"
PKG_ABS="$PWD/$PKG"
# plugin.json at the archive ROOT (what PackageInstaller looks for first); --norsrc
# --noextattr keeps the zip clean (no __MACOSX AppleDouble entries that would add a
# second top-level dir and break payload-root detection).
( cd "$STAGE" && ditto -c -k --norsrc --noextattr . "$PKG_ABS" )
rm -rf "$STAGE" "$DERIVED"

SHA="$(shasum -a 256 "$PKG" | awk '{print $1}')"
echo "OK: built $PKG (plugin version $VERSION)"
echo "    sha256: $SHA"
echo "    Update the suite catalog (docs/catalog/catalog.json) LP-100A entry: latestVersion, url, sha256."
