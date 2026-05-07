import XCTest
@testable import LP100AApp

final class ScalingTests: XCTestCase {
    func testPowerRangeCaps() {
        XCTAssertEqual(RangeScale.max(for: .high), 750)
        XCTAssertEqual(RangeScale.max(for: .mid), 125)
        XCTAssertEqual(RangeScale.max(for: .low), 25)
    }

    func testPowerTickLabels() {
        XCTAssertEqual(RangeScale.ticks(for: .high), ["0", "50", "125", "250", "500", "750"])
        XCTAssertEqual(RangeScale.ticks(for: .mid), ["0", "10", "25", "50", "75", "125"])
        XCTAssertEqual(RangeScale.ticks(for: .low), ["0", "2", "5", "10", "15", "25"])
    }

    func testPowerModeSuffixCasingMatchesLP100ALCD() {
        // Lower-case 'w' for Average is intentional — must match LCD.
        XCTAssertEqual(PowerModeSuffix.suffix(for: .average), "w")
        XCTAssertEqual(PowerModeSuffix.suffix(for: .peakHold), "W")
        XCTAssertEqual(PowerModeSuffix.suffix(for: .tune), "T")
    }

    func testGammaDerivation() {
        // |Γ| = (SWR-1) / (SWR+1)
        let gamma1 = (1.0 - 1) / (1.0 + 1)
        XCTAssertEqual(gamma1, 0)
        let gamma2 = (2.0 - 1) / (2.0 + 1)
        XCTAssertEqual(gamma2, 1.0/3.0, accuracy: 0.0001)
        let gamma3 = (3.0 - 1) / (3.0 + 1)
        XCTAssertEqual(gamma3, 0.5, accuracy: 0.0001)
    }

    func testRBareXFromZAndPhase() {
        // R = |Z| cos(phase), X = |Z| sin(phase)
        let z = 50.0
        let phaseDeg = 0.0
        let phaseRad = phaseDeg * .pi / 180
        XCTAssertEqual(z * cos(phaseRad), 50.0, accuracy: 0.001)
        XCTAssertEqual(z * sin(phaseRad), 0.0, accuracy: 0.001)
    }

    func testSWRBarFractionEdgeCases() {
        let max = SWRScale.max
        XCTAssertEqual((1.0 - 1) / (max - 1), 0)
        XCTAssertEqual((5.0 - 1) / (max - 1), 1.0)
        XCTAssertEqual((3.0 - 1) / (max - 1), 0.5)
    }
}
