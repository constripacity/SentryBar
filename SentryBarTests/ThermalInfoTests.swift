import XCTest
@testable import SentryBar

final class ThermalInfoTests: XCTestCase {

    func testNominalState() {
        let info = ThermalInfo(state: .nominal)
        XCTAssertEqual(info.stateDescription, "Nominal")
        XCTAssertTrue(info.recommendation.contains("cool"))
    }

    func testFairState() {
        let info = ThermalInfo(state: .fair)
        XCTAssertEqual(info.stateDescription, "Fair — Slightly Warm")
        XCTAssertTrue(info.recommendation.contains("closing heavy apps"))
    }

    func testSeriousState() {
        let info = ThermalInfo(state: .serious)
        XCTAssertEqual(info.stateDescription, "Serious — Throttling")
        XCTAssertTrue(info.recommendation.contains("throttled"))
    }

    func testCriticalState() {
        let info = ThermalInfo(state: .critical)
        XCTAssertEqual(info.stateDescription, "Critical — Heavy Throttling")
        XCTAssertTrue(info.recommendation.contains("Severe"))
    }

    func testDefaultStateIsNominal() {
        let info = ThermalInfo()
        XCTAssertEqual(info.state, .nominal)
    }
}
