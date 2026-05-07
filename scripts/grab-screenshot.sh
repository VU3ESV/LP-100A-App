#!/usr/bin/env bash
# Captures the LP-100A app's main window (with any modal sheet) to a PNG.
# Usage: scripts/grab-screenshot.sh <name> [delay-seconds]
#
# Example:
#   scripts/grab-screenshot.sh vector-view 3
#       → docs/screenshots/<name>.png
#
# Tip: pass a delay so you can switch focus to the app and get to the
# desired view before capture fires.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:-}"
DELAY="${2:-2}"

if [ -z "$NAME" ]; then
    echo "usage: $0 <name> [delay-seconds]" >&2
    exit 2
fi

OUT_DIR="$ROOT/docs/screenshots"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$NAME.png"

# Locate the LP-100A window via CGWindowListCopyWindowInfo (no Accessibility
# permission required).
FIND_SCRIPT="$(mktemp -t findwin.XXXXXX).swift"
cat > "$FIND_SCRIPT" <<'SWIFT'
import CoreGraphics
import Foundation
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                      kCGNullWindowID) as? [[String: Any]] ?? []
for w in info {
    let owner = w["kCGWindowOwnerName"] as? String ?? ""
    let layer = w["kCGWindowLayer"] as? Int ?? -1
    guard owner.contains("LP-100A"), layer == 0 else { continue }
    let title = (w["kCGWindowName"] as? String) ?? ""
    // Pick the window with a non-empty title — that's the main app window.
    // Sheets show as separate windows with empty titles.
    if !title.isEmpty {
        if let id = w["kCGWindowNumber"] as? Int { print(id); exit(0) }
    }
}
exit(1)
SWIFT

WIN_ID="$(swift "$FIND_SCRIPT" 2>/dev/null || true)"
rm -f "$FIND_SCRIPT"

if [ -z "${WIN_ID}" ]; then
    echo "==> LP-100A-App window not found. Is the app running?" >&2
    exit 1
fi

echo "==> Capturing window $WIN_ID in ${DELAY}s — switch to the app and arrange the desired view."
sleep "$DELAY"

screencapture -l "$WIN_ID" -x "$OUT"
ls -lh "$OUT"
echo "==> Wrote $OUT"
