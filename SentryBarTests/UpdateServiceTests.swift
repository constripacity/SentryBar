import XCTest
@testable import SentryBar

final class UpdateServiceTests: XCTestCase {

    // MARK: - UpdateInfo

    func testIsNewerWhenLatestIsHigher() {
        let info = UpdateService.UpdateInfo(latestVersion: "0.7.0", currentVersion: "0.6.0", releaseURL: "https://example.com")
        XCTAssertTrue(info.isNewer)
    }

    func testIsNotNewerWhenSameVersion() {
        let info = UpdateService.UpdateInfo(latestVersion: "0.6.0", currentVersion: "0.6.0", releaseURL: "https://example.com")
        XCTAssertFalse(info.isNewer)
    }

    func testIsNotNewerWhenOlderVersion() {
        let info = UpdateService.UpdateInfo(latestVersion: "0.5.0", currentVersion: "0.6.0", releaseURL: "https://example.com")
        XCTAssertFalse(info.isNewer)
    }

    func testIsNewerWithMajorBump() {
        let info = UpdateService.UpdateInfo(latestVersion: "1.0.0", currentVersion: "0.9.9", releaseURL: "https://example.com")
        XCTAssertTrue(info.isNewer)
    }

    func testIsNewerWithPatchBump() {
        let info = UpdateService.UpdateInfo(latestVersion: "0.6.1", currentVersion: "0.6.0", releaseURL: "https://example.com")
        XCTAssertTrue(info.isNewer)
    }
}
