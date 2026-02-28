import XCTest
@testable import SentryBar

final class NetworkConnectionTests: XCTestCase {

    // MARK: - evaluateSuspicion

    func testSuspiciousPort4444() {
        XCTAssertTrue(NetworkConnection.evaluateSuspicion(
            processName: "Safari", remotePort: "4444", remoteAddress: "1.2.3.4"
        ))
    }

    func testSuspiciousPort1337() {
        XCTAssertTrue(NetworkConnection.evaluateSuspicion(
            processName: "Safari", remotePort: "1337", remoteAddress: "1.2.3.4"
        ))
    }

    func testSuspiciousPort31337() {
        XCTAssertTrue(NetworkConnection.evaluateSuspicion(
            processName: "Safari", remotePort: "31337", remoteAddress: "1.2.3.4"
        ))
    }

    func testNormalPortNotSuspicious() {
        XCTAssertFalse(NetworkConnection.evaluateSuspicion(
            processName: "Safari", remotePort: "443", remoteAddress: "1.2.3.4"
        ))
    }

    func testHighPortUnknownProcessIsSuspicious() {
        XCTAssertTrue(NetworkConnection.evaluateSuspicion(
            processName: "mystery_app", remotePort: "50000", remoteAddress: "1.2.3.4"
        ))
    }

    func testHighPortKnownProcessNotSuspicious() {
        XCTAssertFalse(NetworkConnection.evaluateSuspicion(
            processName: "Safari", remotePort: "50000", remoteAddress: "1.2.3.4"
        ))
    }

    func testStandardPortUnknownProcessNotSuspicious() {
        XCTAssertFalse(NetworkConnection.evaluateSuspicion(
            processName: "mystery_app", remotePort: "443", remoteAddress: "1.2.3.4"
        ))
    }

    // MARK: - isKnownProcess

    func testKnownProcessSafari() {
        XCTAssertTrue(NetworkConnection.isKnownProcess("Safari"))
    }

    func testKnownProcessSlack() {
        XCTAssertTrue(NetworkConnection.isKnownProcess("Slack"))
    }

    func testKnownSystemProcess() {
        XCTAssertTrue(NetworkConnection.isKnownProcess("kernel_task"))
    }

    func testUnknownProcess() {
        XCTAssertFalse(NetworkConnection.isKnownProcess("evil_backdoor"))
    }

    // MARK: - isSuspicious with userClassification

    func testIsSuspiciousWhenAllowed() {
        let conn = NetworkConnection(
            processName: "evil", pid: 1, remoteAddress: "1.2.3.4",
            remotePort: "4444", protocol: "TCP", state: "ESTABLISHED",
            userClassification: .allowed, canKill: true, heuristicSuspicious: true
        )
        XCTAssertFalse(conn.isSuspicious, "Allowed classification should override heuristic")
    }

    func testIsSuspiciousWhenBlocked() {
        let conn = NetworkConnection(
            processName: "Safari", pid: 1, remoteAddress: "1.2.3.4",
            remotePort: "443", protocol: "TCP", state: "ESTABLISHED",
            userClassification: .blocked, canKill: true, heuristicSuspicious: false
        )
        XCTAssertTrue(conn.isSuspicious, "Blocked classification should override heuristic")
    }

    func testIsSuspiciousFallsBackToHeuristic() {
        let conn = NetworkConnection(
            processName: "evil", pid: 1, remoteAddress: "1.2.3.4",
            remotePort: "4444", protocol: "TCP", state: "ESTABLISHED",
            userClassification: nil, canKill: true, heuristicSuspicious: true
        )
        XCTAssertTrue(conn.isSuspicious)
    }

    func testNotSuspiciousWhenHeuristicFalse() {
        let conn = NetworkConnection(
            processName: "Safari", pid: 1, remoteAddress: "1.2.3.4",
            remotePort: "443", protocol: "TCP", state: "ESTABLISHED",
            userClassification: nil, canKill: true, heuristicSuspicious: false
        )
        XCTAssertFalse(conn.isSuspicious)
    }

    // MARK: - System processes

    func testSystemProcessCannotBeKilled() {
        XCTAssertTrue(NetworkConnection.systemProcesses.contains("kernel_task"))
        XCTAssertTrue(NetworkConnection.systemProcesses.contains("launchd"))
        XCTAssertTrue(NetworkConnection.systemProcesses.contains("WindowServer"))
    }

    func testAllSuspiciousPorts() {
        let expected: Set<String> = ["4444", "5555", "6666", "1337", "31337", "8888"]
        XCTAssertEqual(NetworkConnection.suspiciousPorts, expected)
    }
}
