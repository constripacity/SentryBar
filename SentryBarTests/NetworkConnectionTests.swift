import XCTest
@testable import SentryBar

final class NetworkConnectionTests: XCTestCase {

    private func connection(
        process: String = "Safari",
        address: String = "1.2.3.4",
        port: String = "443",
        classification: RuleType? = nil,
        flagged: Bool = false
    ) -> NetworkConnection {
        NetworkConnection(
            processName: process,
            pid: 100,
            remoteAddress: address,
            remotePort: port,
            protocol: "TCP",
            state: "ESTABLISHED",
            userClassification: classification,
            canKill: true,
            heuristicSuspicious: flagged
        )
    }

    // MARK: - Private vs external

    func testLocalNetworkAddressesAreRecognised() {
        for address in [
            "127.0.0.1", "10.0.0.5", "192.168.1.30", "172.16.4.1", "172.31.255.1",
            "169.254.1.1", "::1", "fe80::1", "fd00::1",
        ] {
            XCTAssertTrue(
                NetworkConnection.isPrivateAddress(address),
                "\(address) should be treated as local"
            )
        }
    }

    func testPublicAddressesAreExternal() {
        for address in ["142.250.80.46", "8.8.8.8", "172.32.0.1", "2607:f8b0::1"] {
            XCTAssertFalse(
                NetworkConnection.isPrivateAddress(address),
                "\(address) should be treated as external"
            )
        }
        XCTAssertTrue(connection(address: "8.8.8.8").isExternal)
        XCTAssertFalse(connection(address: "192.168.1.30").isExternal)
    }

    // MARK: - Protocol notes

    func testUnencryptedProtocolsAreNoted() {
        XCTAssertNotNil(NetworkConnection.protocolNote(forPort: "23"))
        XCTAssertNotNil(NetworkConnection.protocolNote(forPort: "21"))
        XCTAssertTrue(NetworkConnection.protocolNote(forPort: "23")?.contains("not encrypted") == true)
    }

    func testOrdinaryPortsGetNoNote() {
        // The old model called high ports "suspicious", which fired on WebRTC,
        // QUIC, game servers and every CDN on the machine.
        for port in ["443", "80", "993", "5223", "54321", "61000"] {
            XCTAssertNil(NetworkConnection.protocolNote(forPort: port), "port \(port)")
        }
    }

    // MARK: - Classification

    func testAUserRuleAlwaysWins() {
        XCTAssertFalse(connection(classification: .allowed, flagged: true).isSuspicious)
        XCTAssertTrue(connection(classification: .blocked, flagged: false).isSuspicious)
    }

    func testWithoutARuleTheBaselineDecides() {
        XCTAssertTrue(connection(flagged: true).isSuspicious)
        XCTAssertFalse(connection(flagged: false).isSuspicious)
    }

    // MARK: - Alert identity

    func testAlertKeyIsStableAcrossRefreshes() {
        let first = connection(address: "142.250.80.46")
        let second = connection(address: "142.250.80.99") // same /24
        XCTAssertEqual(first.alertKey, second.alertKey)
    }

    func testAlertKeyDiffersByProcessAndPort() {
        XCTAssertNotEqual(connection(process: "Safari").alertKey, connection(process: "curl").alertKey)
        XCTAssertNotEqual(connection(port: "443").alertKey, connection(port: "8443").alertKey)
    }

    // MARK: - Service labels

    func testWellKnownPortsGetFriendlyLabels() {
        XCTAssertEqual(connection(port: "443").serviceLabel, "Secure web (HTTPS)")
        XCTAssertEqual(connection(port: "53").serviceLabel, "DNS lookup")
        XCTAssertTrue(connection(port: "61000").serviceLabel.contains("High port"))
    }

    func testSystemProcessesAreListed() {
        XCTAssertTrue(NetworkConnection.systemProcesses.contains("launchd"))
        XCTAssertTrue(NetworkConnection.systemProcesses.contains("mDNSResponder"))
        XCTAssertFalse(NetworkConnection.systemProcesses.contains("Safari"))
    }
}
