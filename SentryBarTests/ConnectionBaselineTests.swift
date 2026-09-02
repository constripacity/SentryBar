import XCTest
@testable import SentryBar

/// The behavioural baseline is the product's differentiator, so its rules are
/// tested directly rather than inferred from the UI.
final class ConnectionBaselineTests: XCTestCase {

    private var storageURL: URL!

    override func setUpWithError() throws {
        storageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("baseline-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storageURL)
    }

    private func makeBaseline(learningPeriod: TimeInterval = 0) -> ConnectionBaseline {
        ConnectionBaseline(storageURL: storageURL, learningPeriod: learningPeriod)
    }

    private func connection(
        _ process: String, _ address: String, _ port: String = "443"
    ) -> NetworkConnection {
        NetworkConnection(
            processName: process,
            pid: 1,
            remoteAddress: address,
            remotePort: port,
            protocol: "TCP",
            state: "ESTABLISHED",
            canKill: true,
            heuristicSuspicious: false
        )
    }

    // MARK: - Generalisation

    func testAddressesAreGeneralisedToASubnet() {
        // A CDN answers from a different host every time. Recording exact
        // addresses would make every request "new" forever.
        XCTAssertEqual(ConnectionFingerprint.generalise(address: "142.250.80.46"), "142.250.80.0/24")
        XCTAssertEqual(ConnectionFingerprint.generalise(address: "142.250.80.99"), "142.250.80.0/24")
        XCTAssertNotEqual(
            ConnectionFingerprint.generalise(address: "142.250.80.46"),
            ConnectionFingerprint.generalise(address: "142.251.80.46")
        )
    }

    func testIPv6IsGeneralisedToAPrefix() {
        let a = ConnectionFingerprint.generalise(address: "2607:f8b0:4005:80a::200e")
        let b = ConnectionFingerprint.generalise(address: "2607:f8b0:4005:999::1")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasSuffix("/48"))
    }

    func testSameSubnetIsOneFingerprint() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "142.250.80.46")])
        let second = baseline.observe([connection("Safari", "142.250.80.99")])
        XCTAssertTrue(second.isEmpty, "a different host in the same /24 is not a new destination")
        XCTAssertEqual(baseline.knownEndpointCount, 1)
    }

    // MARK: - Warm-up

    func testNothingIsFlaggedDuringLearning() {
        // Alerting from an empty baseline means alerting on everything.
        let baseline = ConnectionBaseline(storageURL: storageURL, learningPeriod: 3600)
        let findings = baseline.observe([
            connection("Safari", "1.2.3.4"),
            connection("Slack", "5.6.7.8"),
        ])
        XCTAssertTrue(findings.isEmpty)
        XCTAssertFalse(baseline.isWarmedUp)
        XCTAssertEqual(baseline.knownEndpointCount, 2, "but they are still learned")
    }

    func testLearningProgressIsReported() {
        let baseline = ConnectionBaseline(storageURL: storageURL, learningPeriod: 3600)
        XCTAssertLessThan(baseline.learningProgress, 1.0)
        XCTAssertGreaterThanOrEqual(baseline.learningProgress, 0.0)
    }

    // MARK: - Detection

    func testAKnownDestinationIsNotReportedTwice() {
        let baseline = makeBaseline()
        XCTAssertEqual(baseline.observe([connection("Safari", "1.2.3.4")]).count, 1)
        XCTAssertTrue(baseline.observe([connection("Safari", "1.2.3.4")]).isEmpty)
    }

    func testANewDestinationForAKnownProcessIsReported() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4")])
        let findings = baseline.observe([connection("Safari", "9.9.9.0")])
        XCTAssertEqual(findings.count, 1)
        XCTAssertTrue(findings[0].detail.contains("Safari"))
        XCTAssertTrue(findings[0].headline.contains("new destination"))
    }

    func testTheSameEndpointFromADifferentProcessIsNew() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4")])
        XCTAssertEqual(baseline.observe([connection("curl", "1.2.3.4")]).count, 1)
    }

    func testADifferentPortIsANewFingerprint() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4", "443")])
        XCTAssertEqual(baseline.observe([connection("Safari", "1.2.3.4", "8443")]).count, 1)
    }

    func testFindingsExplainThemselves() {
        let baseline = makeBaseline()
        baseline.observe([
            connection("Safari", "1.1.1.0"),
            connection("Safari", "2.2.2.0"),
            connection("Safari", "3.3.3.0"),
        ])
        let findings = baseline.observe([connection("Safari", "4.4.4.0")])
        XCTAssertEqual(findings.count, 1)
        // The explanation names the count it is comparing against.
        XCTAssertTrue(findings[0].detail.contains("3 other destination"))
    }

    // MARK: - Housekeeping

    func testIsKnownDoesNotRecord() {
        let baseline = makeBaseline()
        XCTAssertFalse(baseline.isKnown(connection("Safari", "1.2.3.4")))
        XCTAssertEqual(baseline.knownEndpointCount, 0)
        baseline.observe([connection("Safari", "1.2.3.4")])
        XCTAssertTrue(baseline.isKnown(connection("Safari", "1.2.3.4")))
    }

    func testForgettingAProcessRemovesOnlyItsEntries() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4"), connection("Slack", "5.6.7.8")])
        baseline.forget(process: "Safari")
        XCTAssertEqual(baseline.knownEndpointCount, 1)
        XCTAssertTrue(baseline.isKnown(connection("Slack", "5.6.7.8")))
    }

    func testResetClearsEverythingAndRestartsLearning() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4")])
        baseline.reset()
        XCTAssertEqual(baseline.knownEndpointCount, 0)
    }

    func testStaleEntriesAreForgotten() {
        let baseline = ConnectionBaseline(
            storageURL: storageURL, learningPeriod: 0, retention: 60
        )
        let long_ago = Date().addingTimeInterval(-3600)
        baseline.observe([connection("OldApp", "1.2.3.4")], now: long_ago)
        baseline.observe([connection("NewApp", "5.6.7.8")])
        XCTAssertFalse(baseline.isKnown(connection("OldApp", "1.2.3.4")))
        XCTAssertTrue(baseline.isKnown(connection("NewApp", "5.6.7.8")))
    }

    func testEntryCountIsCapped() {
        let baseline = ConnectionBaseline(
            storageURL: storageURL, learningPeriod: 0, retention: 86_400, maxEntries: 10
        )
        let many = (0..<50).map { connection("Chatty", "10.0.\($0).1") }
        baseline.observe(many)
        XCTAssertLessThanOrEqual(baseline.knownEndpointCount, 10)
    }

    // MARK: - Persistence

    func testBaselineSurvivesARestart() {
        let first = makeBaseline()
        first.observe([connection("Safari", "1.2.3.4")])

        let second = ConnectionBaseline(storageURL: storageURL, learningPeriod: 0)
        XCTAssertTrue(second.isKnown(connection("Safari", "1.2.3.4")))
        XCTAssertTrue(second.observe([connection("Safari", "1.2.3.4")]).isEmpty)
    }

    func testACorruptBaselineFileDoesNotCrash() {
        try? "{ this is not json".write(to: storageURL, atomically: true, encoding: .utf8)
        let baseline = makeBaseline()
        XCTAssertEqual(baseline.knownEndpointCount, 0)
        XCTAssertEqual(baseline.observe([connection("Safari", "1.2.3.4")]).count, 1)
    }

    func testTheBaselineFileIsNotWorldReadable() throws {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4")])
        let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
        XCTAssertEqual(permissions & 0o077, 0, "the baseline should be readable only by its owner")
    }

    // MARK: - What Settings shows

    /// `reset()` and `forget(process:)` were tested here while no view could
    /// call either, and the README told people to use a "Reset baseline"
    /// control in Settings that did not exist. `learnedProcesses()` is what
    /// Settings lists; these assert the shape the view relies on.
    func testLearnedProcessesGroupsByProcessMostEndpointsFirst() {
        let baseline = makeBaseline()
        baseline.observe([
            connection("Safari", "1.2.3.4"),
            connection("Safari", "5.6.7.8"),
            connection("Safari", "9.10.11.12"),
            connection("Mail", "13.14.15.16"),
            connection("Mail", "17.18.19.20"),
            connection("Music", "21.22.23.24"),
        ])

        let learned = baseline.learnedProcesses()
        XCTAssertEqual(learned.map(\.process), ["Safari", "Mail", "Music"])
        XCTAssertEqual(learned.map(\.endpoints), [3, 2, 1])
        XCTAssertEqual(learned.first?.id, "Safari", "the list is identified by process name")
    }

    func testForgettingOneProcessLeavesTheRest() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4"), connection("Mail", "5.6.7.8")])
        baseline.forget(process: "Safari")

        let learned = baseline.learnedProcesses()
        XCTAssertEqual(learned.map(\.process), ["Mail"])
        XCTAssertFalse(baseline.isKnown(connection("Safari", "1.2.3.4")))
        XCTAssertTrue(baseline.isKnown(connection("Mail", "5.6.7.8")))
    }

    func testResetEmptiesTheListAndStartsLearningAgain() {
        let baseline = ConnectionBaseline(storageURL: storageURL, learningPeriod: 3600)
        baseline.observe([connection("Safari", "1.2.3.4")])
        XCTAssertFalse(baseline.learnedProcesses().isEmpty)

        baseline.reset()

        XCTAssertTrue(baseline.learnedProcesses().isEmpty)
        XCTAssertEqual(baseline.knownEndpointCount, 0)
        XCTAssertFalse(baseline.isWarmedUp, "resetting must restart the learning period")
    }

    func testAProcessWithTheSameEndpointTwiceCountsOnce() {
        let baseline = makeBaseline()
        baseline.observe([connection("Safari", "1.2.3.4"), connection("Safari", "1.2.3.4")])
        XCTAssertEqual(baseline.learnedProcesses().first?.endpoints, 1)
    }
}
