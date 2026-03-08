import XCTest
@testable import SentryBar

final class MenuBarIconOptionTests: XCTestCase {

    func testAllOptionsHaveUniqueSymbols() {
        let symbols = MenuBarIconOption.allOptions.map(\.symbol)
        XCTAssertEqual(symbols.count, Set(symbols).count, "Duplicate icon symbols found")
    }

    func testAllOptionsHaveLabels() {
        for option in MenuBarIconOption.allOptions {
            XCTAssertFalse(option.label.isEmpty, "Icon \(option.symbol) has empty label")
        }
    }

    func testDefaultIconIsInOptions() {
        let defaultIcon = "shield.checkered"
        XCTAssertTrue(MenuBarIconOption.allOptions.contains { $0.symbol == defaultIcon })
    }

    func testMinimumOptionCount() {
        XCTAssertGreaterThanOrEqual(MenuBarIconOption.allOptions.count, 5, "Should have at least 5 icon options")
    }
}
