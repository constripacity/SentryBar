import XCTest
@testable import SentryBar

final class BatteryInfoTests: XCTestCase {

    func testDefaultValues() {
        let info = BatteryInfo()
        XCTAssertEqual(info.healthPercent, 100)
        XCTAssertEqual(info.cycleCount, 0)
        XCTAssertEqual(info.currentCharge, 100)
        XCTAssertFalse(info.isCharging)
        XCTAssertNil(info.timeRemaining)
    }

    func testTimeRemainingFormattedNil() {
        let info = BatteryInfo()
        XCTAssertEqual(info.timeRemainingFormatted, "Calculating...")
    }

    func testTimeRemainingFormattedZeroMinutes() {
        var info = BatteryInfo()
        info.timeRemaining = 0
        XCTAssertEqual(info.timeRemainingFormatted, "0h 0m")
    }

    func testTimeRemainingFormattedMinutesOnly() {
        var info = BatteryInfo()
        info.timeRemaining = 45
        XCTAssertEqual(info.timeRemainingFormatted, "0h 45m")
    }

    func testTimeRemainingFormattedHoursAndMinutes() {
        var info = BatteryInfo()
        info.timeRemaining = 150
        XCTAssertEqual(info.timeRemainingFormatted, "2h 30m")
    }

    func testTimeRemainingFormattedExactHours() {
        var info = BatteryInfo()
        info.timeRemaining = 120
        XCTAssertEqual(info.timeRemainingFormatted, "2h 0m")
    }
}
