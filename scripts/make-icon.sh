#!/usr/bin/env bash
# Generates an AppIcon.icns from a single 1024x1024 SVG/PNG source.
# Usage: scripts/make-icon.sh [path/to/source.png]
#
# Produces: dist/AppIcon.icns
#
# If no source is supplied, generates a placeholder PNG via Python's Pillow
# OR falls back to a SwiftUI-style ColorGenerator using sips. The placeholder
# matches the LP-100A LCD aesthetic: dark teal-on-black "LP" mark.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
ICONSET="$DIST/AppIcon.iconset"
SOURCE="${1:-$DIST/AppIcon-source.png}"

mkdir -p "$DIST" "$ICONSET"

generate_placeholder() {
    cat > "$DIST/_icon.swift" <<'SWIFT'
import AppKit
import CoreGraphics

let size = CGSize(width: 1024, height: 1024)
let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil,
                    width: Int(size.width),
                    height: Int(size.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Background gradient (dark case → near-black)
let grad = CGGradient(colorsSpace: cs,
                      colors: [CGColor(red: 0x1c/255.0, green: 0x23/255.0, blue: 0x2b/255.0, alpha: 1),
                               CGColor(red: 0x07/255.0, green: 0x09/255.0, blue: 0x0c/255.0, alpha: 1)] as CFArray,
                      locations: [0, 1])!
let path = CGPath(roundedRect: CGRect(origin: .zero, size: size),
                  cornerWidth: 200, cornerHeight: 200, transform: nil)
ctx.addPath(path)
ctx.clip()
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 0, y: size.height),
                       end: CGPoint(x: 0, y: 0),
                       options: [])

// Inner LCD rectangle
let lcd = CGRect(x: 140, y: 240, width: size.width - 280, height: size.height - 480)
ctx.setFillColor(CGColor(red: 0x06/255.0, green: 0x08/255.0, blue: 0x0a/255.0, alpha: 1))
ctx.addPath(CGPath(roundedRect: lcd, cornerWidth: 30, cornerHeight: 30, transform: nil))
ctx.fillPath()

// Bargraph stripes (decorative)
ctx.setFillColor(CGColor(red: 0x18/255.0, green: 0xd4/255.0, blue: 0xb3/255.0, alpha: 0.85))
let bar = CGRect(x: lcd.minX + 60, y: lcd.minY + 100, width: lcd.width * 0.65, height: 80)
ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 8, cornerHeight: 8, transform: nil))
ctx.fillPath()

ctx.setFillColor(CGColor(red: 0xff/255.0, green: 0xba/255.0, blue: 0x2b/255.0, alpha: 1))
let attr: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Menlo-Bold", size: 280) ?? NSFont.boldSystemFont(ofSize: 280),
    .foregroundColor: NSColor(red: 1.0, green: 0xba/255.0, blue: 0x2b/255.0, alpha: 1)
]
let text = NSAttributedString(string: "LP", attributes: attr)
let line = CTLineCreateWithAttributedString(text)
ctx.textPosition = CGPoint(x: lcd.minX + 60, y: lcd.maxY - 200)
CTLineDraw(line, ctx)

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
let data = rep.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

    swift "$DIST/_icon.swift" "$1"
    rm -f "$DIST/_icon.swift"
}

if [ ! -f "$SOURCE" ]; then
    echo "==> Generating placeholder icon at $SOURCE"
    generate_placeholder "$SOURCE"
fi

echo "==> Generating .iconset from $SOURCE"
for sz in 16 32 64 128 256 512 1024; do
    sips -z "$sz" "$sz" "$SOURCE" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    if [ "$sz" -lt 1024 ]; then
        dbl=$((sz * 2))
        sips -z "$dbl" "$dbl" "$SOURCE" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    fi
done

# Re-name to match Apple's expected sizes for .iconset
mv "$ICONSET/icon_64x64.png"      "$ICONSET/icon_32x32@2x.png"
mv "$ICONSET/icon_64x64@2x.png"   "$ICONSET/icon_32x32@2x.png" 2>/dev/null || true

iconutil -c icns "$ICONSET" -o "$DIST/AppIcon.icns"
echo "==> Wrote $DIST/AppIcon.icns"
