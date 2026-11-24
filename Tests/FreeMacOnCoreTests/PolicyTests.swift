import XCTest
@testable import FreeMacOnCore
final class PolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    func testPower() {
        XCTAssertEqual(Policy.power("Now drawing from 'AC Power'\n -InternalBattery 8%"), .ac)
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n -InternalBattery-0 22%; discharging"), .battery(22))
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n 150%"), .unknown)
        XCTAssertEqual(Policy.power("garbage"), .unknown)
    }
    func testSleepReadback() {
        XCTAssertEqual(Policy.sleepDisabled("System-wide power settings:\n SleepDisabled 1\nCurrently in use:"), true)
        XCTAssertEqual(Policy.sleepDisabled("Currently in use:\n SleepDisabled 0"), false)
        XCTAssertEqual(Policy.sleepDisabled("Currently in use:\n sleep 10"), false)
        XCTAssertNil(Policy.sleepDisabled("error"))
        XCTAssertNil(Policy.sleepDisabled("Currently in use:\n SleepDisabled ?"))
    }
    func testGuardrails() {
        func check(_ deadline: Date? = nil, _ heartbeat: Date? = nil, _ power: Power = .ac, _ hot: Bool = false, _ override: Bool = true) -> Guardrail? {
            Policy.stopReason(now: now, deadline: deadline, heartbeat: heartbeat, power: power, hot: hot, overrideOK: override)
        }
        XCTAssertNil(check(nil, now)); XCTAssertEqual(check(now, now), .deadline)
        XCTAssertEqual(check(nil, now, .battery(22)), .batteryLow)
        XCTAssertNil(check(nil, now, .battery(23)))
        XCTAssertEqual(check(nil, now, .unknown), .powerUnknown)
        XCTAssertEqual(check(nil, now, .ac, true), .thermal)
        XCTAssertEqual(check(), .heartbeatLost)
        XCTAssertEqual(check(nil, now.addingTimeInterval(-26)), .heartbeatLost)
        XCTAssertEqual(check(nil, now.addingTimeInterval(6)), .heartbeatLost)
        XCTAssertEqual(check(nil, now, .ac, false, false), .overrideLost)
        XCTAssertNil(Policy.stopReason(now: now, deadline: nil, heartbeat: nil, power: .ac, hot: false, requiresHeartbeat: false))
    }
    func testDurationBounds() {
        XCTAssertFalse(Policy.validClosedMinutes(0)); XCTAssertTrue(Policy.validClosedMinutes(1)); XCTAssertTrue(Policy.validClosedMinutes(480)); XCTAssertFalse(Policy.validClosedMinutes(481))
    }
    func testAdversarialReadback() {
        XCTAssertNil(Policy.sleepDisabled("Currently in use:\n"))
        XCTAssertNil(Policy.sleepDisabled("System-wide power settings:\n garbage"))
        XCTAssertNil(Policy.sleepDisabled("Currently in use:\n SleepDisabled 0\n SleepDisabled 1"))
        XCTAssertNil(Policy.sleepDisabled("Currently in use:\n sleep -1"))
        XCTAssertNil(Policy.sleepDisabled("Currently in use:\n SleepDisabled 0 trailing"))
        XCTAssertEqual(Policy.sleepDisabled("Currently in use:\n sleep 10 (sleep prevented by process)"), false)
        XCTAssertEqual(Policy.sleepDisabled("System-wide power settings:\n SleepDisabled 1"), true)
    }
    func testAdversarialPower() {
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n -InternalBattery-0 -1%"), .unknown)
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n -InternalBattery-0 101%"), .unknown)
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n -InternalBattery-0 0%"), .battery(0))
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n -InternalBattery-0 100%"), .battery(100))
        XCTAssertEqual(Policy.power("not AC Power"), .unknown)
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n External UPS 99%"), .unknown)
        XCTAssertEqual(Policy.power("Now drawing from 'Battery Power'\n -InternalBattery-0 70%\n -InternalBattery-1 50%"), .unknown)
    }
    func testHeartbeatBoundary() {
        func check(_ age: TimeInterval) -> Guardrail? {
            Policy.stopReason(now: now, deadline: nil, heartbeat: now.addingTimeInterval(-age), power: .ac, hot: false)
        }
        XCTAssertNil(check(25)); XCTAssertEqual(check(25.01), .heartbeatLost)
        XCTAssertNil(check(-5)); XCTAssertEqual(check(-5.01), .heartbeatLost)
    }
    func testQuoting() { XCTAssertEqual(Policy.shellQuote("a'b"), "'a'\\''b'") }
}
