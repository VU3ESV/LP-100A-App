import SwiftUI

// Color and spacing tokens mirroring :root in the server's reference web
// client (internal/web/static/index.html). Keep names parallel so the two
// faces stay visually in lockstep.
enum Tokens {
    static let bezel       = Color(hex: 0x1a1d22)
    static let bezelEdge   = Color(hex: 0x0a0c0e)
    static let caseBg      = Color(hex: 0x11151a)
    static let lcd         = Color(hex: 0x06080a)
    static let lcdBorder   = Color(hex: 0x2a323c)
    static let grid        = Color(hex: 0x1d2630)
    static let tick        = Color(hex: 0x4a5566)
    static let bar         = Color(hex: 0x18d4b3)
    static let barTop      = Color(hex: 0x2bf0cd)
    static let barBottom   = Color(hex: 0x0aa088)
    static let barGlow     = Color(red: 24/255, green: 212/255, blue: 179/255, opacity: 0.4)
    static let peak        = Color(hex: 0xb9fff2)
    static let power       = Color(hex: 0xffba2b)
    static let powerGlow   = Color(red: 1.0, green: 186/255, blue: 43/255, opacity: 0.35)
    static let swrFg       = Color(hex: 0xe8eef2)
    static let green       = Color(hex: 0x2ecc71)
    static let yellow      = Color(hex: 0xf1c40f)
    static let red         = Color(hex: 0xe74c3c)
    static let muted       = Color(hex: 0x6f7a87)
    static let accent      = Color(hex: 0x18d4b3)
    static let label       = Color(hex: 0x8a96a4)
    static let dashed      = Color(hex: 0x1f2a35)

    static let warnTop     = Color(hex: 0xffe35e)
    static let warnMid     = Color(hex: 0xf1c40f)
    static let warnBottom  = Color(hex: 0xb8910b)
    static let badTop      = Color(hex: 0xff8b7e)
    static let badMid      = Color(hex: 0xe74c3c)
    static let badBottom   = Color(hex: 0xa52a1d)
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// Mirrors POWER_MODE_SUFFIX in the web client. Lower-case 'w' for Average
// is intentional and must not be uppercased (LP-100A LCD convention).
enum PowerModeSuffix {
    static func suffix(for mode: PeakMode) -> String {
        switch mode {
        case .average:   return "w"
        case .peakHold:  return "W"
        case .tune:      return "T"
        }
    }
}

enum RangeScale {
    static func max(for range: PowerRange) -> Double {
        switch range {
        case .high: return 750
        case .mid:  return 125
        case .low:  return 25
        }
    }

    static func ticks(for range: PowerRange) -> [String] {
        switch range {
        case .high: return ["0", "50", "125", "250", "500", "750"]
        case .mid:  return ["0", "10", "25", "50", "75", "125"]
        case .low:  return ["0", "2", "5", "10", "15", "25"]
        }
    }
}

enum SWRScale {
    static let max: Double = 5.0
    static let warnThreshold: Double = 1.5
    static let badThreshold: Double = 2.0
}
