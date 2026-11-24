import Foundation

public enum Power: Equatable { case ac, battery(Int), unknown }
public enum Guardrail: String, Equatable {
    case deadline, batteryLow, powerUnknown, thermal, heartbeatLost, overrideLost
}
public enum Policy {
    public static let batteryFloor = 22
    public static let heartbeatTimeout: TimeInterval = 25
    public static let maxClosedMinutes = 480
    public static func validClosedMinutes(_ minutes: Int) -> Bool { (1...maxClosedMinutes).contains(minutes) }
    public static func sleepDisabled(_ output: String) -> Bool? {
        // Only accept actual pmset output; absence is normal when the flag is off.
        guard output.contains("System-wide power settings:") || output.contains("Currently in use:") || output.contains("Active Profiles:") else { return nil }
        let lines = output.split(separator: "\n").map { $0.split(whereSeparator: { $0.isWhitespace }) }
        let values = lines.filter { $0.first == "SleepDisabled" || $0.first == "disablesleep" }
        if values.isEmpty { return false }
        guard values.allSatisfy({ $0.count == 2 && ($0[1] == "0" || $0[1] == "1") }) else { return nil }
        return values.contains { $0[1] == "1" }
    }
    public static func power(_ output: String) -> Power {
        guard let header = output.split(separator: "\n").first else { return .unknown }
        if header.contains("AC Power") { return .ac }
        guard header.contains("Battery Power") else { return .unknown }
        guard let match = output.range(of: #"\b[0-9]{1,3}%"#, options: .regularExpression),
              let level = Int(output[match].dropLast()), (0...100).contains(level) else { return .unknown }
        return .battery(level)
    }
    public static func stopReason(now: Date, deadline: Date?, heartbeat: Date?, power: Power, hot: Bool, overrideOK: Bool = true, requiresHeartbeat: Bool = true) -> Guardrail? {
        if let deadline, now >= deadline { return .deadline }
        if hot { return .thermal }
        switch power {
        case .unknown: return .powerUnknown
        case .battery(let level) where level <= batteryFloor: return .batteryLow
        default: break
        }
        if requiresHeartbeat {
            guard let heartbeat, now.timeIntervalSince(heartbeat) >= -5, now.timeIntervalSince(heartbeat) <= heartbeatTimeout else { return .heartbeatLost }
        }
        if !overrideOK { return .overrideLost }
        return nil
    }
    public static func shellQuote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
