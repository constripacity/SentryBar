import XCTest
@testable import SentryBar

@MainActor
final class NotificationLogTests: XCTestCase {

    // MARK: - NotificationLogEntry

    func testEntryCreation() {
        let entry = NotificationLogEntry(type: .thermal, title: "Test Title", body: "Test Body")
        XCTAssertEqual(entry.type, .thermal)
        XCTAssertEqual(entry.title, "Test Title")
        XCTAssertEqual(entry.body, "Test Body")
        XCTAssertNotNil(entry.id)
    }

    func testEntryTimestampIsRecent() {
        let before = Date()
        let entry = NotificationLogEntry(type: .battery, title: "T", body: "B")
        let after = Date()
        XCTAssertGreaterThanOrEqual(entry.timestamp, before)
        XCTAssertLessThanOrEqual(entry.timestamp, after)
    }

    func testEntryUniqueIDs() {
        let a = NotificationLogEntry(type: .suspicious, title: "A", body: "A")
        let b = NotificationLogEntry(type: .suspicious, title: "A", body: "A")
        XCTAssertNotEqual(a.id, b.id)
    }

    // MARK: - NotificationType

    func testNotificationTypeIcons() {
        XCTAssertEqual(NotificationType.thermal.icon, "thermometer.high")
        XCTAssertEqual(NotificationType.battery.icon, "battery.25")
        XCTAssertEqual(NotificationType.suspicious.icon, "exclamationmark.triangle.fill")
        XCTAssertEqual(NotificationType.bandwidth.icon, "arrow.up.arrow.down.circle.fill")
    }

    func testNotificationTypeLabels() {
        XCTAssertEqual(NotificationType.thermal.label, "Thermal")
        XCTAssertEqual(NotificationType.battery.label, "Battery")
        XCTAssertEqual(NotificationType.suspicious.label, "Suspicious")
        XCTAssertEqual(NotificationType.bandwidth.label, "Bandwidth")
    }

    // MARK: - NotificationLog

    func testLogStartsEmpty() {
        let log = NotificationLog()
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(log.count, 0)
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testAddEntry() {
        let log = NotificationLog()
        log.add(type: .thermal, title: "Thermal Warning", body: "System is hot")
        XCTAssertEqual(log.count, 1)
        XCTAssertFalse(log.isEmpty)
        XCTAssertEqual(log.entries.first?.type, .thermal)
        XCTAssertEqual(log.entries.first?.title, "Thermal Warning")
    }

    func testEntriesAreNewestFirst() {
        let log = NotificationLog()
        log.add(type: .thermal, title: "First", body: "1")
        log.add(type: .battery, title: "Second", body: "2")
        log.add(type: .suspicious, title: "Third", body: "3")

        XCTAssertEqual(log.entries[0].title, "Third")
        XCTAssertEqual(log.entries[1].title, "Second")
        XCTAssertEqual(log.entries[2].title, "First")
    }

    func testRingBufferCapsAt50() {
        let log = NotificationLog()
        for i in 0..<60 {
            log.add(type: .thermal, title: "Entry \(i)", body: "Body")
        }
        XCTAssertEqual(log.count, 50)
        XCTAssertEqual(log.entries.first?.title, "Entry 59")
        XCTAssertEqual(log.entries.last?.title, "Entry 10")
    }

    func testClearAll() {
        let log = NotificationLog()
        log.add(type: .thermal, title: "A", body: "1")
        log.add(type: .battery, title: "B", body: "2")
        XCTAssertEqual(log.count, 2)

        log.clearAll()
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(log.count, 0)
    }

    func testMultipleTypes() {
        let log = NotificationLog()
        log.add(type: .thermal, title: "T", body: "t")
        log.add(type: .battery, title: "B", body: "b")
        log.add(type: .suspicious, title: "S", body: "s")
        log.add(type: .bandwidth, title: "BW", body: "bw")

        let types = Set(log.entries.map(\.type))
        XCTAssertEqual(types.count, 4)
    }
}
