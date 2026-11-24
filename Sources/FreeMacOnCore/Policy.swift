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
        if values.isEmpty {
            // A truncated or header-only response must not be mistaken for proof of restoration.
            return lines.contains { $0.count >= 2 && $0[0] == "sleep" && Int($0[1]).map { $0 >= 0 } == true } ? false : nil
        }
        guard values.allSatisfy({ $0.count == 2 && ($0[1] == "0" || $0[1] == "1") }) else { return nil }
        let unique = Set(values.map { String($0[1]) })
        guard unique.count == 1 else { return nil }
        return unique.contains("1")
    }
    public static func power(_ output: String) -> Power {
        guard let header = output.split(separator: "\n").first else { return .unknown }
        if header.trimmingCharacters(in: .whitespaces) == "Now drawing from 'AC Power'" { return .ac }
        guard header.trimmingCharacters(in: .whitespaces) == "Now drawing from 'Battery Power'" else { return .unknown }
        let batteries = output.split(separator: "\n").filter { $0.contains("InternalBattery") }
        guard batteries.count == 1, let line = batteries.first,
              let match = line.range(of: #"(?<![0-9-])\b[0-9]{1,3}%"#, options: .regularExpression),
              let level = Int(line[match].dropLast()), (0...100).contains(level) else { return .unknown }
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
