import XCTest
@testable import SentryBar

/// The alert engine is what makes SentryBar's notifications worth reading, so
/// its suppression rules are tested directly.
///
/// Before it existed there was a pair of `lastAlertTime` fields and a flat
/// 60-second cooldown shared by unrelated conditions, which meant (a) a machine
/// in a steady bad state produced one notification per polling interval forever,
/// and (b) a thermal alert could silence a network alert.
final class AlertEngineTests: XCTestCase {

    private func makeAlert(
        _ key: String,
        severity: AlertSeverity = .notice,
        type: NotificationType = .suspicious
    ) -> MonitorAlert {
        MonitorAlert(
                    key: key, type: type, severity: severity, title: "T", body: "B")
    }

    // MARK: - Delivery and deduplication

    func testAFirstAlertIsDelivered() {
        let engine = AlertEngine()
        guard case .deliver = engine.raise(makeAlert("a")) else {
            return XCTFail("first occurrence should be delivered")
        }
    }

    func testARepeatWithinTheIntervalIsCoalesced() {
        let engine = AlertEngine(repeatInterval: 3600)
        _ = engine.raise(makeAlert("a"))
        guard case let .coalesced(_, occurrences) = engine.raise(makeAlert("a")) else {
            return XCTFail("a repeat should be coalesced, not re-delivered")
        }
        XCTAssertEqual(occurrences, 2)
        XCTAssertEqual(engine.currentAlerts.count, 1, "and it stays one entry")
    }

    func testARepeatAfterTheIntervalIsDeliveredAgain() {
        let engine = AlertEngine(repeatInterval: 60)
        let start = Date()
        _ = engine.raise(makeAlert("a"), now: start)
        let later = start.addingTimeInterval(120)
        guard case .deliver = engine.raise(makeAlert("a"), now: later) else {
            return XCTFail("a persistent condition should remind, eventually")
        }
    }

    func testUnrelatedAlertsDoNotSuppressEachOther() {
        let engine = AlertEngine()
        guard case .deliver = engine.raise(makeAlert("a", type: .thermal)) else {
            return XCTFail("first alert should deliver")
        }
        guard case .deliver = engine.raise(makeAlert("b", type: .bandwidth)) else {
            return XCTFail("a different condition must not be silenced by the first")
        }
    }

    // MARK: - Rate limiting

    func testAGlobalRateLimitAppliesAcrossKeys() {
        let engine = AlertEngine(windowLength: 600, maxPerWindow: 3)
        for index in 0..<3 {
            guard case .deliver = engine.raise(makeAlert("k\(index)")) else {
                return XCTFail("the first three should deliver")
            }
        }
        guard case .rateLimited = engine.raise(makeAlert("k4")) else {
            return XCTFail("the fourth in the window should be held")
        }
    }

    func testTheWindowSlides() {
        let engine = AlertEngine(windowLength: 60, maxPerWindow: 1)
        let start = Date()
        _ = engine.raise(makeAlert("a"), now: start)
        guard case .rateLimited = engine.raise(makeAlert("b"), now: start) else {
            return XCTFail("should be limited inside the window")
        }
        guard case .deliver = engine.raise(makeAlert("c"), now: start.addingTimeInterval(120))
        else {
            return XCTFail("should deliver once the window has passed")
        }
    }

    func testARateLimitedAlertIsStillRecordedAsActive() {
        let engine = AlertEngine(windowLength: 600, maxPerWindow: 1)
        _ = engine.raise(makeAlert("a"))
        _ = engine.raise(makeAlert("b"))
        XCTAssertEqual(engine.currentAlerts.count, 2, "held is not the same as forgotten")
    }

    // MARK: - Severity floor

    func testAlertsBelowTheThresholdAreDropped() {
        let engine = AlertEngine(minimumSeverity: .warning)
        guard case .belowThreshold = engine.raise(makeAlert("a", severity: .info)) else {
            return XCTFail("info should be below a warning threshold")
        }
        guard case .deliver = engine.raise(makeAlert("b", severity: .warning)) else {
            return XCTFail("warnings should still deliver")
        }
    }

    // MARK: - Snoozing

    func testSnoozingAKeySuppressesOnlyThatKey() {
        let engine = AlertEngine()
        engine.snooze(key: "a", for: 3600)
        guard case .snoozed = engine.raise(makeAlert("a")) else {
            return XCTFail("a snoozed key should be suppressed")
        }
        guard case .deliver = engine.raise(makeAlert("b")) else {
            return XCTFail("other keys are unaffected")
        }
    }

    func testSnoozingATypeSuppressesTheWholeType() {
        let engine = AlertEngine()
        engine.snooze(type: .bandwidth, for: 3600)
        guard case .snoozed = engine.raise(makeAlert("a", type: .bandwidth)) else {
            return XCTFail("the type should be suppressed")
        }
        guard case .deliver = engine.raise(makeAlert("b", type: .thermal)) else {
            return XCTFail("a different type is unaffected")
        }
    }

    func testASnoozeExpires() {
        let engine = AlertEngine()
        let start = Date()
        engine.snooze(key: "a", for: 60, now: start)
        XCTAssertTrue(engine.isSnoozed(key: "a", now: start.addingTimeInterval(10)))
        XCTAssertFalse(engine.isSnoozed(key: "a", now: start.addingTimeInterval(120)))
    }

    // MARK: - Clearing

    func testClearingMakesTheNextOccurrenceNewAgain() {
        let engine = AlertEngine(repeatInterval: 3600)
        _ = engine.raise(makeAlert("a"))
        engine.clear(key: "a")
        guard case .deliver = engine.raise(makeAlert("a")) else {
            return XCTFail("after the condition ended, its return is news again")
        }
    }

    func testRetainOnlyClearsEverythingElse() {
        let engine = AlertEngine()
        _ = engine.raise(makeAlert("a"))
        _ = engine.raise(makeAlert("b"))
        engine.retainOnly(keys: ["a"])
        XCTAssertEqual(engine.currentAlerts.map(\.key), ["a"])
    }

    // MARK: - Ordering and counting

    func testAlertsAreSortedWorstFirst() {
        let engine = AlertEngine(minimumSeverity: .info)
        _ = engine.raise(makeAlert("low", severity: .info))
        _ = engine.raise(makeAlert("high", severity: .warning))
        XCTAssertEqual(engine.currentAlerts.first?.key, "high")
    }

    func testAcknowledgingReducesTheUnreadCount() {
        let engine = AlertEngine()
        _ = engine.raise(makeAlert("a"))
        XCTAssertEqual(engine.unacknowledgedCount, 1)
        engine.acknowledge(key: "a")
        XCTAssertEqual(engine.unacknowledgedCount, 0)
    }
}
