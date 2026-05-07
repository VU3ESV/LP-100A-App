import Foundation

// Wire-protocol mirror of the LP-100A WebSocket server.
// Reference: VU3ESV/LP-100A-Server PROPOSAL.md §4.

enum PowerRange: String, Codable, Equatable {
    case high, mid, low
}

enum PeakMode: String, Codable, Equatable {
    case average
    case peakHold = "peak_hold"
    case tune
}

enum AlarmSetpoint: String, Codable, Equatable {
    case off
    case s1_5 = "1.5"
    case s2_0 = "2.0"
    case s2_5 = "2.5"
    case s3_0 = "3.0"
    case user
}

struct Telemetry: Codable, Equatable {
    var powerW: Double
    var zOhm: Double
    var phaseDeg: Double
    var swr: Double
    var dbm: Double
    var dbw: Double
    var range: PowerRange
    var mode: PeakMode
    var alarmSetpoint: AlarmSetpoint
    var alarmTripped: Bool
    var callsign: String

    enum CodingKeys: String, CodingKey {
        case powerW = "power_w"
        case zOhm = "z_ohm"
        case phaseDeg = "phase_deg"
        case swr, dbm, dbw, range, mode
        case alarmSetpoint = "alarm_setpoint"
        case alarmTripped = "alarm_tripped"
        case callsign
    }
}

enum ServerFrame: Decodable, Equatable {
    case telemetry(seq: Int, ts: String, data: Telemetry)
    case heartbeat(seq: Int, ts: String)
    case status(level: String, msg: String)
    case ack(ref: String, ok: Bool, error: String?)
    case unknown(type: String)

    private enum K: String, CodingKey {
        case type, seq, ts, data, level, msg, ref, ok, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "telemetry":
            self = .telemetry(
                seq: (try? c.decode(Int.self, forKey: .seq)) ?? 0,
                ts: (try? c.decode(String.self, forKey: .ts)) ?? "",
                data: try c.decode(Telemetry.self, forKey: .data)
            )
        case "heartbeat":
            self = .heartbeat(
                seq: (try? c.decode(Int.self, forKey: .seq)) ?? 0,
                ts: (try? c.decode(String.self, forKey: .ts)) ?? ""
            )
        case "status":
            self = .status(
                level: (try? c.decode(String.self, forKey: .level)) ?? "info",
                msg: (try? c.decode(String.self, forKey: .msg)) ?? ""
            )
        case "ack":
            self = .ack(
                ref: (try? c.decode(String.self, forKey: .ref)) ?? "",
                ok: (try? c.decode(Bool.self, forKey: .ok)) ?? false,
                error: try? c.decode(String.self, forKey: .error)
            )
        default:
            self = .unknown(type: type)
        }
    }
}

enum CommandAction: String, Codable {
    case alarmStep = "alarm_step"
    case modeStep = "mode_step"
    case peakToggle = "peak_toggle"
}

enum ClientFrame: Encodable {
    case command(id: String, action: CommandAction)
    case resync

    private enum K: String, CodingKey { case type, id, action }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        switch self {
        case .command(let id, let action):
            try c.encode("command", forKey: .type)
            try c.encode(id, forKey: .id)
            try c.encode(action.rawValue, forKey: .action)
        case .resync:
            try c.encode("resync", forKey: .type)
        }
    }
}
