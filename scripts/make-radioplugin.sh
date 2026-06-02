#!/bin/bash
# Build LP100AExtension.appex and package it as `LP100A.radioplugin` -- the installable
# bundle the Amateur Radio Suite browses + installs (zip of plugin.json + the .appex).
#
#   ./scripts/make-radioplugin.sh            # -> dist/LP100A.radioplugin (+ its sha256)
#
# Running the installed plugin needs Developer-ID signing + extension approval; this
# produces an ad-hoc-signed package suitable for the catalog/discovery flow and testing.
set -euo pipefail
cd "$(dirname "$0")/.."

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

echo "==> Building $SCHEME (.appex)"
DERIVED="$(mktemp -d)"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build >/dev/null

APPEX="$(/usr/bin/find "$DERIVED/Build/Products" -name 'LP100AExtension.appex' -maxdepth 3 | head -1)"
[ -n "$APPEX" ] || { echo "ERROR: LP100AExtension.appex not found"; exit 1; }

echo "==> Assembling $PKG"
STAGE="$(mktemp -d)"
cp "Xcode/Extension/plugin.json" "$STAGE/plugin.json"
cp -R "$APPEX" "$STAGE/"

rm -rf "$DIST"
mkdir -p "$DIST"
PKG_ABS="$PWD/$PKG"
# plugin.json at the archive ROOT (what PackageInstaller looks for first); --norsrc
# --noextattr keeps the zip clean (no __MACOSX AppleDouble entries that would add a
# second top-level dir and break payload-root detection).
( cd "$STAGE" && ditto -c -k --norsrc --noextattr . "$PKG_ABS" )
rm -rf "$STAGE" "$DERIVED"

SHA="$(shasum -a 256 "$PKG" | awk '{print $1}')"
echo "OK: built $PKG"
echo "    sha256: $SHA"
echo "    Add this to the suite catalog (docs/catalog/catalog.json) as the LP-100A entry."
