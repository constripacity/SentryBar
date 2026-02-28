import XCTest
@testable import SentryBar

final class ConnectionRuleTests: XCTestCase {

    // MARK: - ConnectionRule

    func testRuleCreation() {
        let rule = ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Safari")
        XCTAssertEqual(rule.ruleType, .allowed)
        XCTAssertEqual(rule.matchField, .processName)
        XCTAssertEqual(rule.matchValue, "Safari")
        XCTAssertNil(rule.note)
    }

    func testRuleWithNote() {
        let rule = ConnectionRule(ruleType: .blocked, matchField: .remoteAddress, matchValue: "1.2.3.4", note: "Suspicious server")
        XCTAssertEqual(rule.note, "Suspicious server")
        XCTAssertEqual(rule.ruleType, .blocked)
    }

    // MARK: - MatchField

    func testMatchFieldLabels() {
        XCTAssertEqual(MatchField.processName.label, "Process Name")
        XCTAssertEqual(MatchField.remoteAddress.label, "Remote Address")
        XCTAssertEqual(MatchField.remotePort.label, "Port")
    }

    func testMatchFieldIcons() {
        XCTAssertEqual(MatchField.processName.icon, "person.fill")
        XCTAssertEqual(MatchField.remoteAddress.icon, "globe")
        XCTAssertEqual(MatchField.remotePort.icon, "number")
    }

    // MARK: - ConnectionRuleStore

    func testRuleStoreAddAndFind() {
        let store = ConnectionRuleStore()
        store.rules = [] // Start clean (don't load from disk)

        let rule = ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Safari")
        store.rules.append(rule)

        let conn = NetworkConnection(
            processName: "Safari", pid: 100, remoteAddress: "1.2.3.4",
            remotePort: "443", protocol: "TCP", state: "ESTABLISHED",
            canKill: true, heuristicSuspicious: false
        )

        let found = store.ruleFor(connection: conn)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.ruleType, .allowed)
    }

    func testRuleStoreMatchByAddress() {
        let store = ConnectionRuleStore()
        store.rules = []

        let rule = ConnectionRule(ruleType: .blocked, matchField: .remoteAddress, matchValue: "10.0.0.1")
        store.rules.append(rule)

        let conn = NetworkConnection(
            processName: "evil_app", pid: 200, remoteAddress: "10.0.0.1",
            remotePort: "8080", protocol: "TCP", state: "ESTABLISHED",
            canKill: true, heuristicSuspicious: false
        )

        XCTAssertTrue(store.isBlocked(conn))
        XCTAssertFalse(store.isAllowed(conn))
    }

    func testRuleStoreMatchByPort() {
        let store = ConnectionRuleStore()
        store.rules = []

        let rule = ConnectionRule(ruleType: .blocked, matchField: .remotePort, matchValue: "4444")
        store.rules.append(rule)

        let conn = NetworkConnection(
            processName: "app", pid: 300, remoteAddress: "1.2.3.4",
            remotePort: "4444", protocol: "TCP", state: "ESTABLISHED",
            canKill: true, heuristicSuspicious: true
        )

        XCTAssertTrue(store.isBlocked(conn))
    }

    func testRuleStoreNoMatch() {
        let store = ConnectionRuleStore()
        store.rules = []

        let conn = NetworkConnection(
            processName: "Safari", pid: 100, remoteAddress: "1.2.3.4",
            remotePort: "443", protocol: "TCP", state: "ESTABLISHED",
            canKill: true, heuristicSuspicious: false
        )

        XCTAssertNil(store.ruleFor(connection: conn))
        XCTAssertFalse(store.isAllowed(conn))
        XCTAssertFalse(store.isBlocked(conn))
    }

    func testRuleStoreRemoveRule() {
        let store = ConnectionRuleStore()
        store.rules = []

        let rule = ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Safari")
        store.rules.append(rule)
        XCTAssertEqual(store.rules.count, 1)

        store.rules.removeAll { $0.id == rule.id }
        XCTAssertEqual(store.rules.count, 0)
    }

    func testRuleStoreCounts() {
        let store = ConnectionRuleStore()
        store.rules = []

        store.rules.append(ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Safari"))
        store.rules.append(ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Slack"))
        store.rules.append(ConnectionRule(ruleType: .blocked, matchField: .remoteAddress, matchValue: "1.2.3.4"))

        XCTAssertEqual(store.allowedCount, 2)
        XCTAssertEqual(store.blockedCount, 1)
    }

    func testRuleStoreClearAll() {
        let store = ConnectionRuleStore()
        store.rules = []

        store.rules.append(ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Safari"))
        store.rules.append(ConnectionRule(ruleType: .blocked, matchField: .processName, matchValue: "evil"))
        XCTAssertEqual(store.rules.count, 2)

        store.rules.removeAll()
        XCTAssertEqual(store.rules.count, 0)
    }

    func testFirstRuleWins() {
        let store = ConnectionRuleStore()
        store.rules = []

        store.rules.append(ConnectionRule(ruleType: .allowed, matchField: .processName, matchValue: "Safari"))
        store.rules.append(ConnectionRule(ruleType: .blocked, matchField: .processName, matchValue: "Safari"))

        let conn = NetworkConnection(
            processName: "Safari", pid: 100, remoteAddress: "1.2.3.4",
            remotePort: "443", protocol: "TCP", state: "ESTABLISHED",
            canKill: true, heuristicSuspicious: false
        )

        let found = store.ruleFor(connection: conn)
        XCTAssertEqual(found?.ruleType, .allowed, "First matching rule should win")
    }
}
