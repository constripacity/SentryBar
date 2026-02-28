import XCTest
@testable import SentryBar

final class NetworkServiceTests: XCTestCase {

    let service = NetworkService()

    // MARK: - parseLsofOutput

    func testParseLsofTypicalLine() {
        let output = "Safari    1234  user   15u  IPv4 0x1234  0t0  TCP 192.168.1.100:52341->142.250.80.46:443 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        let conn = connections[0]
        XCTAssertEqual(conn.processName, "Safari")
        XCTAssertEqual(conn.pid, 1234)
        XCTAssertEqual(conn.protocol, "TCP")
        XCTAssertEqual(conn.remoteAddress, "142.250.80.46")
        XCTAssertEqual(conn.remotePort, "443")
        XCTAssertEqual(conn.state, "ESTABLISHED")
        XCTAssertTrue(conn.canKill)
        XCTAssertFalse(conn.heuristicSuspicious)
    }

    func testParseLsofMultipleLines() {
        let output = """
        Safari    1234  user   15u  IPv4 0x1234  0t0  TCP 192.168.1.100:52341->142.250.80.46:443 (ESTABLISHED)
        Slack     5678  user   20u  IPv4 0x5678  0t0  TCP 192.168.1.100:52342->34.107.243.93:443 (ESTABLISHED)
        """
        let connections = service.parseLsofOutput(output)
        XCTAssertEqual(connections.count, 2)
        XCTAssertEqual(connections[0].processName, "Safari")
        XCTAssertEqual(connections[1].processName, "Slack")
    }

    func testParseLsofEmptyOutput() {
        let connections = service.parseLsofOutput("")
        XCTAssertTrue(connections.isEmpty)
    }

    func testParseLsofMalformedLine() {
        let output = "short line"
        let connections = service.parseLsofOutput(output)
        XCTAssertTrue(connections.isEmpty)
    }

    func testParseLsofSuspiciousPort() {
        let output = "evil_app  999  user   5u  IPv4 0xabc  0t0  TCP 10.0.0.1:12345->1.2.3.4:4444 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertTrue(connections[0].heuristicSuspicious)
        XCTAssertEqual(connections[0].remotePort, "4444")
    }

    func testParseLsofSystemProcess() {
        let output = "launchd   1     root   10u  IPv4 0x1111  0t0  TCP 10.0.0.1:443->1.2.3.4:443 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertFalse(connections[0].canKill, "System process should not be killable")
    }

    func testParseLsofUDP() {
        let output = "mDNSResp  100  user   8u  IPv4 0x2222  0t0  UDP 10.0.0.1:5353->224.0.0.251:5353 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].protocol, "UDP")
    }

    // MARK: - parseLsofOutput Edge Cases

    func testParseLsofEscapedProcessName() {
        let output = "Brave\\x20 3401  user   24u  IPv4 0x1234  0t0  TCP 192.168.1.103:49398->140.82.114.22:443 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].processName, "Brave ")
        XCTAssertEqual(connections[0].remoteAddress, "140.82.114.22")
        XCTAssertEqual(connections[0].remotePort, "443")
    }

    func testParseLsofIPv6Connection() {
        let output = "rapportd  652  user   16u  IPv6 0xb5dd  0t0  TCP [2001:db8::1:c2c:e5f5:7f3e:3dd6]:49310->[2001:db8::2:a5cf:9f62:318:9a62]:59232 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].processName, "rapportd")
        XCTAssertEqual(connections[0].remoteAddress, "2001:db8::2:a5cf:9f62:318:9a62")
        XCTAssertEqual(connections[0].remotePort, "59232")
    }

    func testParseLsofExtractsState() {
        let output = "Safari    1234  user   15u  IPv4 0x1234  0t0  TCP 192.168.1.100:52341->142.250.80.46:443 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections[0].state, "ESTABLISHED")
    }

    func testParseLsofCloseWaitState() {
        let output = "Safari    1234  user   15u  IPv4 0x1234  0t0  TCP 192.168.1.100:52341->142.250.80.46:443 (CLOSE_WAIT)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].state, "CLOSE_WAIT")
    }

    func testParseLsofNumericProcessName() {
        let output = "2.1.63    3104  user   11u  IPv4 0x1234  0t0  TCP 192.168.1.103:49393->160.79.104.10:443 (ESTABLISHED)"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].processName, "2.1.63")
        XCTAssertEqual(connections[0].pid, 3104)
    }

    func testParseLsofNoStateField() {
        let output = "Safari    1234  user   15u  IPv4 0x1234  0t0  TCP 192.168.1.100:52341->142.250.80.46:443"
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 1)
        XCTAssertEqual(connections[0].state, "UNKNOWN")
        XCTAssertEqual(connections[0].remotePort, "443")
    }

    func testParseLsofRealMultiLineOutput() {
        let output = """
        rapportd   652 user   16u  IPv6 0xb5dd8dfd29ef617e      0t0  TCP [2001:db8::1:c2c:e5f5:7f3e:3dd6]:49310->[2001:db8::2:a5cf:9f62:318:9a62]:59232 (ESTABLISHED)
        2.1.63    3104 user   18u  IPv4 0x66254c2ff5539946      0t0  TCP 192.168.1.103:49393->160.79.104.10:443 (ESTABLISHED)
        Brave\\x20 3401 user   24u  IPv4 0x179d144b658eecd6      0t0  TCP 192.168.1.103:49398->140.82.114.22:443 (ESTABLISHED)
        """
        let connections = service.parseLsofOutput(output)

        XCTAssertEqual(connections.count, 3)
        XCTAssertEqual(connections[0].processName, "rapportd")
        XCTAssertEqual(connections[0].remoteAddress, "2001:db8::2:a5cf:9f62:318:9a62")
        XCTAssertEqual(connections[1].processName, "2.1.63")
        XCTAssertEqual(connections[1].remoteAddress, "160.79.104.10")
        XCTAssertEqual(connections[2].processName, "Brave ")
        XCTAssertEqual(connections[2].remoteAddress, "140.82.114.22")
    }

    // MARK: - parseConnectionString

    func testParseConnectionStringWithArrow() {
        let result = service.parseConnectionString("192.168.1.100:52341->142.250.80.46:443")
        XCTAssertEqual(result.address, "142.250.80.46")
        XCTAssertEqual(result.port, "443")
    }

    func testParseConnectionStringWithoutArrow() {
        let result = service.parseConnectionString("142.250.80.46:443")
        XCTAssertEqual(result.address, "142.250.80.46")
        XCTAssertEqual(result.port, "443")
    }

    func testParseConnectionStringNoPort() {
        let result = service.parseConnectionString("noport")
        XCTAssertEqual(result.address, "noport")
        XCTAssertEqual(result.port, "?")
    }

    func testParseConnectionStringIPv6() {
        let result = service.parseConnectionString("[2001:db8::2:a5cf:9f62:318:9a62]:59232")
        XCTAssertEqual(result.address, "2001:db8::2:a5cf:9f62:318:9a62")
        XCTAssertEqual(result.port, "59232")
    }

    func testParseConnectionStringIPv6Arrow() {
        let result = service.parseConnectionString("[2001:db8::1:c2c:e5f5:7f3e:3dd6]:49310->[2001:db8::2:a5cf:9f62:318:9a62]:59232")
        XCTAssertEqual(result.address, "2001:db8::2:a5cf:9f62:318:9a62")
        XCTAssertEqual(result.port, "59232")
    }

    func testParseConnectionStringWildcard() {
        let result = service.parseConnectionString("*:*")
        XCTAssertEqual(result.address, "*")
        XCTAssertEqual(result.port, "*")
    }

    // MARK: - unescapeLsof

    func testUnescapeLsofSpace() {
        XCTAssertEqual(service.unescapeLsof("Brave\\x20"), "Brave ")
    }

    func testUnescapeLsofNoEscapes() {
        XCTAssertEqual(service.unescapeLsof("Safari"), "Safari")
    }

    func testUnescapeLsofMultipleEscapes() {
        XCTAssertEqual(service.unescapeLsof("A\\x20B\\x20C"), "A B C")
    }

    func testUnescapeLsofTab() {
        XCTAssertEqual(service.unescapeLsof("App\\x09Name"), "App\tName")
    }

    // MARK: - parsePsOutput

    func testParsePsOutput() {
        let output = """
          PID COMM              %CPU
          100 /usr/bin/Safari    12.5
          200 /usr/bin/Slack      3.2
        """
        let processes = service.parsePsOutput(output)
        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].name, "Safari")
        XCTAssertEqual(processes[0].pid, 100)
        XCTAssertEqual(processes[0].cpuUsage, 12.5)
        XCTAssertEqual(processes[1].name, "Slack")
    }

    func testParsePsOutputSkipsZeroCPU() {
        let output = """
          PID COMM              %CPU
          100 /usr/bin/Safari    0.0
        """
        let processes = service.parsePsOutput(output)
        XCTAssertTrue(processes.isEmpty)
    }

    func testParsePsOutputEmpty() {
        let processes = service.parsePsOutput("")
        XCTAssertTrue(processes.isEmpty)
    }

    func testParsePsOutputExtractsLastPathComponent() {
        let output = """
          PID COMM              %CPU
          100 /System/Library/Frameworks/Something/Safari    5.0
        """
        let processes = service.parsePsOutput(output)
        XCTAssertEqual(processes.count, 1)
        XCTAssertEqual(processes[0].name, "Safari")
    }
}
