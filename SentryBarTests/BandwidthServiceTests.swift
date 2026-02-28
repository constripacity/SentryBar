import XCTest
@testable import SentryBar

final class BandwidthServiceTests: XCTestCase {

    let service = BandwidthService()

    // MARK: - parseBandwidthOutput

    func testParseTwoBlocks() {
        let output = """
        time,bytes_in,bytes_out
        Safari.1234,1000,500
        Slack.5678,2000,300

        time,bytes_in,bytes_out
        Safari.1234,5000,2000
        Slack.5678,3000,1000
        """

        let snapshot = service.parseBandwidthOutput(output)
        XCTAssertEqual(snapshot.processes.count, 2)

        let safari = snapshot.processes.first { $0.processName == "Safari" }
        XCTAssertNotNil(safari)
        XCTAssertEqual(safari?.bytesIn, 5000)
        XCTAssertEqual(safari?.bytesOut, 2000)
        XCTAssertEqual(safari?.pid, 1234)
    }

    func testParseSingleBlock() {
        let output = """
        Safari.1234,1024,512
        """

        let snapshot = service.parseBandwidthOutput(output)
        XCTAssertEqual(snapshot.processes.count, 1)
        XCTAssertEqual(snapshot.processes[0].processName, "Safari")
        XCTAssertEqual(snapshot.processes[0].bytesIn, 1024)
        XCTAssertEqual(snapshot.processes[0].bytesOut, 512)
    }

    func testParseSkipsZeroTraffic() {
        let output = """
        Safari.1234,0,0
        Slack.5678,1000,500
        """

        let snapshot = service.parseBandwidthOutput(output)
        XCTAssertEqual(snapshot.processes.count, 1)
        XCTAssertEqual(snapshot.processes[0].processName, "Slack")
    }

    func testParseSkipsHeaderLines() {
        let output = """
        time,bytes_in,bytes_out
        Safari.1234,1000,500
        """

        let snapshot = service.parseBandwidthOutput(output)
        XCTAssertEqual(snapshot.processes.count, 1)
        XCTAssertEqual(snapshot.processes[0].processName, "Safari")
    }

    func testParseEmptyOutput() {
        let snapshot = service.parseBandwidthOutput("")
        XCTAssertTrue(snapshot.processes.isEmpty)
    }

    func testParseMalformedLines() {
        let output = """
        badline
        also,bad
        Safari.1234,1000,500
        """

        let snapshot = service.parseBandwidthOutput(output)
        XCTAssertEqual(snapshot.processes.count, 1)
    }

    func testParseAggregatesMultipleConnectionsSameProcess() {
        let output = """
        Safari.1234,1000,500
        Safari.1234,2000,300
        """

        let snapshot = service.parseBandwidthOutput(output)
        XCTAssertEqual(snapshot.processes.count, 1)

        let safari = snapshot.processes[0]
        XCTAssertEqual(safari.bytesIn, 3000)
        XCTAssertEqual(safari.bytesOut, 800)
    }

    // MARK: - parseProcessField

    func testParseProcessFieldNormal() {
        let result = service.parseProcessField("Safari.1234")
        XCTAssertEqual(result.name, "Safari")
        XCTAssertEqual(result.pid, 1234)
    }

    func testParseProcessFieldWithDotsInName() {
        let result = service.parseProcessField("com.apple.Safari.1234")
        XCTAssertEqual(result.name, "com.apple.Safari")
        XCTAssertEqual(result.pid, 1234)
    }

    func testParseProcessFieldNoDot() {
        let result = service.parseProcessField("Safari")
        XCTAssertEqual(result.name, "Safari")
        XCTAssertEqual(result.pid, 0)
    }

    func testParseProcessFieldDotButNoPID() {
        let result = service.parseProcessField("com.apple.Safari")
        // "Safari" is not a valid PID, so the whole string becomes the name
        XCTAssertEqual(result.name, "com.apple.Safari")
        XCTAssertEqual(result.pid, 0)
    }

    // MARK: - BandwidthSnapshot

    func testSnapshotTotals() {
        let snapshot = BandwidthSnapshot(timestamp: Date(), duration: 2.0, processes: [
            ProcessBandwidth(processName: "Safari", pid: 1, bytesIn: 1000, bytesOut: 500),
            ProcessBandwidth(processName: "Slack", pid: 2, bytesIn: 2000, bytesOut: 300)
        ])
        XCTAssertEqual(snapshot.totalBytesIn, 3000)
        XCTAssertEqual(snapshot.totalBytesOut, 800)
    }

    func testSnapshotTopConsumers() {
        let snapshot = BandwidthSnapshot(timestamp: Date(), duration: 2.0, processes: [
            ProcessBandwidth(processName: "Low", pid: 1, bytesIn: 100, bytesOut: 50),
            ProcessBandwidth(processName: "High", pid: 2, bytesIn: 10000, bytesOut: 5000),
            ProcessBandwidth(processName: "Medium", pid: 3, bytesIn: 1000, bytesOut: 500)
        ])

        let top2 = snapshot.topConsumers(limit: 2)
        XCTAssertEqual(top2.count, 2)
        XCTAssertEqual(top2[0].processName, "High")
        XCTAssertEqual(top2[1].processName, "Medium")
    }

    func testSnapshotEmpty() {
        let snapshot = BandwidthSnapshot.empty
        XCTAssertTrue(snapshot.processes.isEmpty)
        XCTAssertEqual(snapshot.totalBytesIn, 0)
        XCTAssertEqual(snapshot.totalBytesOut, 0)
        XCTAssertEqual(snapshot.duration, 0)
    }

    // MARK: - Rate Calculations

    func testSnapshotRateCalculation() {
        let snapshot = BandwidthSnapshot(timestamp: Date(), duration: 2.0, processes: [
            ProcessBandwidth(processName: "Safari", pid: 1, bytesIn: 2048, bytesOut: 1024)
        ])
        XCTAssertEqual(snapshot.rateIn, 1024.0, accuracy: 0.01)
        XCTAssertEqual(snapshot.rateOut, 512.0, accuracy: 0.01)
    }

    func testSnapshotRateZeroDuration() {
        let snapshot = BandwidthSnapshot(timestamp: Date(), duration: 0, processes: [
            ProcessBandwidth(processName: "Safari", pid: 1, bytesIn: 1000, bytesOut: 500)
        ])
        XCTAssertEqual(snapshot.rateIn, 0)
        XCTAssertEqual(snapshot.rateOut, 0)
    }

    func testProcessBandwidthRate() {
        let pb = ProcessBandwidth(processName: "Safari", pid: 1, bytesIn: 10240, bytesOut: 5120)
        XCTAssertEqual(pb.rateIn(duration: 2.0), 5120.0, accuracy: 0.01)
        XCTAssertEqual(pb.rateOut(duration: 2.0), 2560.0, accuracy: 0.01)
        XCTAssertEqual(pb.rateIn(duration: 0), 0)
    }

    func testParseBandwidthOutputWithDuration() {
        let output = """
        time,bytes_in,bytes_out
        Safari.1234,1000,500

        time,bytes_in,bytes_out
        Safari.1234,5000,2000
        """
        let snapshot = service.parseBandwidthOutput(output, duration: 3.5)
        XCTAssertEqual(snapshot.duration, 3.5, accuracy: 0.01)
    }
}
