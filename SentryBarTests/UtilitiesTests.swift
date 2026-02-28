import XCTest
@testable import SentryBar

final class UtilitiesTests: XCTestCase {

    // MARK: - formatBytes

    func testFormatBytesZero() {
        XCTAssertEqual(formatBytes(0), "0 B")
    }

    func testFormatBytesSmall() {
        XCTAssertEqual(formatBytes(500), "500 B")
    }

    func testFormatBytesKB() {
        XCTAssertEqual(formatBytes(1024), "1 KB")
    }

    func testFormatBytesKBFraction() {
        XCTAssertEqual(formatBytes(2560), "2 KB") // 2.5 KB, banker's rounding
    }

    func testFormatBytesMB() {
        XCTAssertEqual(formatBytes(1_048_576), "1.0 MB")
    }

    func testFormatBytesMBFraction() {
        XCTAssertEqual(formatBytes(1_572_864), "1.5 MB")
    }

    func testFormatBytesGB() {
        XCTAssertEqual(formatBytes(1_073_741_824), "1.0 GB")
    }

    func testFormatBytesLargeGB() {
        XCTAssertEqual(formatBytes(5_368_709_120), "5.0 GB")
    }

    // MARK: - ProcessBandwidth formatting

    func testProcessBandwidthFormatted() {
        let pb = ProcessBandwidth(processName: "Safari", pid: 1, bytesIn: 1_048_576, bytesOut: 524_288)
        XCTAssertEqual(pb.formattedIn, "1.0 MB")
        XCTAssertEqual(pb.formattedOut, "512 KB") // 0.5 MB = 512 KB, %.0f format
        XCTAssertEqual(pb.totalBytes, 1_572_864)
    }

    // MARK: - Date extension

    func testDateShortTimeString() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = formatter.date(from: "2026-01-15 14:30:45")!
        XCTAssertEqual(date.shortTimeString, "14:30:45")
    }

    // MARK: - formatRate

    func testFormatRateZero() {
        XCTAssertEqual(formatRate(0), "0 B/s")
    }

    func testFormatRateBytes() {
        XCTAssertEqual(formatRate(500), "500 B/s")
    }

    func testFormatRateKBs() {
        XCTAssertEqual(formatRate(1536), "1.5 KB/s")
    }

    func testFormatRateMBs() {
        XCTAssertEqual(formatRate(1_572_864), "1.5 MB/s")
    }

    func testFormatRateGBs() {
        XCTAssertEqual(formatRate(1_610_612_736), "1.5 GB/s")
    }

    func testFormatRateSmallKBs() {
        XCTAssertEqual(formatRate(1024), "1.0 KB/s")
    }

    // MARK: - Optional<String> extension

    func testOptionalStringOrEmptyWithValue() {
        let value: String? = "hello"
        XCTAssertEqual(value.orEmpty, "hello")
    }

    func testOptionalStringOrEmptyWithNil() {
        let value: String? = nil
        XCTAssertEqual(value.orEmpty, "")
    }
}
