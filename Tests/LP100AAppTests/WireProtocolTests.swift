import XCTest
@testable import LP100AApp

final class WireProtocolTests: XCTestCase {
    func testTelemetryFrameRoundtrip() throws {
        let json = """
        {
          "type": "telemetry",
          "seq": 12345,
          "ts": "2026-05-07T18:22:01.103Z",
          "data": {
            "power_w": 1457.00,
            "z_ohm": 49.3,
            "phase_deg": 5.0,
            "swr": 1.02,
            "dbm": 61.6,
            "dbw": 31.6,
            "range": "high",
            "mode": "tune",
            "alarm_setpoint": "2.0",
            "alarm_tripped": false,
            "callsign": "N8LP"
          }
        }
        """.data(using: .utf8)!

        let frame = try JSONDecoder().decode(ServerFrame.self, from: json)
        guard case .telemetry(let seq, _, let data) = frame else {
            XCTFail("Expected telemetry frame, got \(frame)")
            return
        }
        XCTAssertEqual(seq, 12345)
        XCTAssertEqual(data.powerW, 1457.0, accuracy: 0.001)
        XCTAssertEqual(data.swr, 1.02, accuracy: 0.001)
        XCTAssertEqual(data.range, .high)
        XCTAssertEqual(data.mode, .tune)
        XCTAssertEqual(data.alarmSetpoint, .s2_0)
        XCTAssertFalse(data.alarmTripped)
        XCTAssertEqual(data.callsign, "N8LP")
    }

    func testHeartbeatFrame() throws {
        let json = #"{"type":"heartbeat","seq":1,"ts":"x"}"#.data(using: .utf8)!
        let frame = try JSONDecoder().decode(ServerFrame.self, from: json)
        guard case .heartbeat(let seq, _) = frame else {
            XCTFail("Expected heartbeat")
            return
        }
        XCTAssertEqual(seq, 1)
    }

    func testStatusFrame() throws {
        let json = #"{"type":"status","level":"warn","msg":"serial reopened after 1.3s gap"}"#.data(using: .utf8)!
        let frame = try JSONDecoder().decode(ServerFrame.self, from: json)
        guard case .status(let level, let msg) = frame else {
            XCTFail("Expected status")
            return
        }
        XCTAssertEqual(level, "warn")
        XCTAssertEqual(msg, "serial reopened after 1.3s gap")
    }

    func testAckFrame() throws {
        let json = #"{"type":"ack","ref":"abc-1","ok":true}"#.data(using: .utf8)!
        let frame = try JSONDecoder().decode(ServerFrame.self, from: json)
        guard case .ack(let ref, let ok, _) = frame else {
            XCTFail("Expected ack")
            return
        }
        XCTAssertEqual(ref, "abc-1")
        XCTAssertTrue(ok)
    }

    func testCommandEncoding() throws {
        let frame: ClientFrame = .command(id: "abc-1", action: .modeStep)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(frame)
        let s = String(data: data, encoding: .utf8)
        XCTAssertEqual(s, #"{"action":"mode_step","id":"abc-1","type":"command"}"#)
    }

    func testResyncEncoding() throws {
        let frame: ClientFrame = .resync
        let data = try JSONEncoder().encode(frame)
        let s = String(data: data, encoding: .utf8)
        XCTAssertEqual(s, #"{"type":"resync"}"#)
    }

    func testUnknownFrameDoesNotThrow() throws {
        let json = #"{"type":"future_thing","x":1}"#.data(using: .utf8)!
        let frame = try JSONDecoder().decode(ServerFrame.self, from: json)
        guard case .unknown(let t) = frame else {
            XCTFail("Expected unknown")
            return
        }
        XCTAssertEqual(t, "future_thing")
    }
}
