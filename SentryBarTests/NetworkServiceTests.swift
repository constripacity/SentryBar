import XCTest
@testable import SentryBar

/// `lsof -F` field-output parsing.
///
/// The previous parser split the default table on whitespace and indexed fixed
/// column numbers. That breaks whenever a process name contains a space, or a
/// column is wide enough to shift the rest of the row — both of which happen on
/// a real Mac ("Google Chrome Helper", long IPv6 addresses). Field output has
/// one `<tag><value>` per line and cannot shift.
final class NetworkServiceTests: XCTestCase {

    let service = NetworkService()

    // MARK: - Field output

    func testParsesASingleEstablishedConnection() {
        let output = """
        p1234
        cSafari
        f15
        PTCP
        n192.168.1.100:52341->142.250.80.46:443
        TST=ESTABLISHED
        """
        let connections = service.parseLsofFieldOutput(output)

        XCTAssertEqual(connections.count, 1)
        guard let conn = connections.first else {
            return XCTFail("expected one connection")
        }
        XCTAssertEqual(conn.processName, "Safari")
        XCTAssertEqual(conn.pid, 1234)
        XCTAssertEqual(conn.protocol, "TCP")
        XCTAssertEqual(conn.remoteAddress, "142.250.80.46")
        XCTAssertEqual(conn.remotePort, "443")
        XCTAssertEqual(conn.state, "ESTABLISHED")
    }

    func testProcessNamesContainingSpacesSurvive() {
        // The old whitespace-splitting parser turned this into "Google".
        let output = """
        p900
        cGoogle Chrome Helper
        f7
        PTCP
        n10.0.0.5:60001->172.217.16.142:443
        TST=ESTABLISHED
        """
        let connections = service.parseLsofFieldOutput(output)
        XCTAssertEqual(connections.first?.processName, "Google Chrome Helper")
    }

    func testOneProcessWithSeveralSockets() {
        let output = """
        p1234
        cSafari
        f15
        PTCP
        n192.168.1.100:52341->142.250.80.46:443
        TST=ESTABLISHED
        f16
        PTCP
        n192.168.1.100:52342->140.82.121.4:443
        TST=ESTABLISHED
        """
        let connections = service.parseLsofFieldOutput(output)
        XCTAssertEqual(connections.count, 2)
        XCTAssertTrue(connections.allSatisfy { $0.processName == "Safari" })
        XCTAssertEqual(Set(connections.map(\.remoteAddress)), ["142.250.80.46", "140.82.121.4"])
    }

    func testIPv6AddressesKeepTheirColons() {
        let output = """
        p2000
        cMail
        f9
        PTCP
        n[2601:646:4000::1]:52341->[2607:f8b0:4005:80a::200e]:993
        TST=ESTABLISHED
        """
        let connections = service.parseLsofFieldOutput(output)
        XCTAssertEqual(connections.first?.remoteAddress, "2607:f8b0:4005:80a::200e")
        XCTAssertEqual(connections.first?.remotePort, "993")
    }

    func testListeningSocketsAreExcludedByDefault() {
        let output = """
        p400
        cnginx
        f6
        PTCP
        n*:8080
        TST=LISTEN
        """
        XCTAssertTrue(service.parseLsofFieldOutput(output).isEmpty)
        XCTAssertEqual(service.parseLsofFieldOutput(output, includeListening: true).count, 1)
    }

    func testTransientStatesAreIgnored() {
        let output = """
        p777
        cSafari
        f4
        PTCP
        n10.0.0.5:1234->1.2.3.4:443
        TST=TIME_WAIT
        """
        XCTAssertTrue(service.parseLsofFieldOutput(output).isEmpty)
    }

    func testEmptyAndGarbageInputProduceNothing() {
        XCTAssertTrue(service.parseLsofFieldOutput("").isEmpty)
        XCTAssertTrue(service.parseLsofFieldOutput("not lsof output at all\n\n").isEmpty)
    }

    func testSystemProcessesAreNotKillable() {
        let output = """
        p1
        claunchd
        f3
        PTCP
        n10.0.0.5:100->1.2.3.4:443
        TST=ESTABLISHED
        """
        XCTAssertEqual(service.parseLsofFieldOutput(output).first?.canKill, false)
    }

    func testNothingIsFlaggedByTheParserItself() {
        // Suspicion now comes from ConnectionBaseline, not from the parser.
        let output = """
        p1234
        cSomeUnknownApp
        f15
        PTCP
        n10.0.0.5:52341->1.2.3.4:54321
        TST=ESTABLISHED
        """
        XCTAssertEqual(service.parseLsofFieldOutput(output).first?.heuristicSuspicious, false)
    }

    // MARK: - Connection strings

    func testParseConnectionString() {
        XCTAssertEqual(service.parseConnectionString("1.2.3.4:5678").address, "1.2.3.4")
        XCTAssertEqual(service.parseConnectionString("1.2.3.4:5678").port, "5678")
        XCTAssertEqual(service.parseConnectionString("10.0.0.1:80->1.2.3.4:443").address, "1.2.3.4")
        XCTAssertEqual(service.parseConnectionString("[::1]:8080").address, "::1")
    }

    // MARK: - ps output

    func testParsePsOutputHandlesNamesWithSpaces() {
        let output = """
          PID COMM             %CPU
          1234 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome  45.2
          5678 /usr/bin/idle     0.0
        """
        let processes = service.parsePsOutput(output)
        XCTAssertEqual(processes.count, 1) // the 0.0 row is dropped
        XCTAssertEqual(processes.first?.name, "Google Chrome")
        XCTAssertEqual(processes.first?.cpuUsage, 45.2)
    }

    // MARK: - lsof escapes

    func testUnescapeLsofHexSequences() {
        XCTAssertEqual(service.unescapeLsof("My\\x20App"), "My App")
        XCTAssertEqual(service.unescapeLsof("Plain"), "Plain")
        XCTAssertEqual(service.unescapeLsof("Bad\\xZZ"), "Bad\\xZZ")
    }

    // MARK: - Terminating

    func testTerminateRefusesPidZeroAndOne() {
        XCTAssertFalse(service.terminate(pid: 0, expectedName: "x").succeeded)
        XCTAssertFalse(service.terminate(pid: 1, expectedName: "launchd").succeeded)
    }

    func testTerminateRefusesWhenTheNameNoLongerMatches() {
        // Our own process definitely exists, and is definitely not named this.
        let outcome = service.terminate(
            pid: ProcessInfo.processInfo.processIdentifier,
            expectedName: "definitely-not-this-process"
        )
        XCTAssertFalse(outcome.succeeded)
        if case let .refused(reason) = outcome {
            XCTAssertTrue(reason.contains("reused") || reason.contains("not"))
        } else {
            XCTFail("expected a refusal, got \(outcome)")
        }
    }

    func testProcessInfoReadsOurOwnProcess() {
        let info = service.processInfo(pid: ProcessInfo.processInfo.processIdentifier)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.uid, getuid())
    }

    func testProcessInfoReturnsNilForAnImpossiblePid() {
        XCTAssertNil(service.processInfo(pid: 999_999))
    }
}
