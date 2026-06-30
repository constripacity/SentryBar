import XCTest
@testable import SentryBar

/// Pins the Remora verdict JSON → Swift decoding contract (the integration surface with the
/// Remora engine). The fixture mirrors a real POST /triage response shape.
final class RemoraVerdictTests: XCTestCase {

    private let hostileJSON = """
    {
      "trust": "hostile",
      "summary": "2 high-severity indicators found.",
      "findings": [
        {"check": "exposure.cleartext_auth", "severity": "high",
         "title": "Credentials exposed over cleartext FTP", "detail": "...",
         "evidence": {"protocols": ["ftp"]}, "recommendation": "Switch to SFTP."},
        {"check": "tls.legacy_version", "severity": "medium",
         "title": "Obsolete TLS negotiated", "detail": "...",
         "evidence": {}, "recommendation": "Avoid."}
      ],
      "stats": {
        "risk_score": {"score": 60, "band": "high",
          "components": {"anchor": 60, "extra_highs": 0, "corroboration": 0, "confirmed": 0},
          "drivers": [{"check": "exposure.cleartext_auth", "severity": "high", "points": 60}]},
        "attack": {
          "techniques": [
            {"id": "T1040", "name": "Network Sniffing", "tactic": "Credential Access",
             "checks": ["exposure.cleartext_auth", "tls.legacy_version"]},
            {"id": "T1557", "name": "Adversary-in-the-Middle", "tactic": "Credential Access",
             "checks": ["tls.legacy_version"]}],
          "tactics": ["Credential Access"], "by_check": {}},
        "ranking": {"focus": "exposure.cleartext_auth",
          "order": ["exposure.cleartext_auth", "tls.legacy_version"], "ranked": []}
      }
    }
    """

    private let benignJSON = """
    {
      "trust": "trusted", "summary": "Network looks ordinary.", "findings": [],
      "stats": {
        "risk_score": {"score": 0, "band": "clean",
          "components": {"anchor": 0, "extra_highs": 0, "corroboration": 0, "confirmed": 0},
          "drivers": []},
        "attack": {"techniques": [], "tactics": [], "by_check": {}},
        "ranking": {"focus": null, "order": [], "ranked": []}
      }
    }
    """

    private func decode(_ json: String) throws -> RemoraVerdict {
        try JSONDecoder().decode(RemoraVerdict.self, from: Data(json.utf8))
    }

    func testDecodesHostileVerdict() throws {
        let v = try decode(hostileJSON)
        XCTAssertEqual(v.trust, "hostile")
        XCTAssertEqual(v.riskScore, 60)
        XCTAssertEqual(v.band, .high)
        XCTAssertEqual(v.findings.count, 2)
        XCTAssertEqual(v.findings.first?.check, "exposure.cleartext_auth")
        XCTAssertEqual(v.focus, "exposure.cleartext_auth")
    }

    func testDecodesAttackTechniques() throws {
        let v = try decode(hostileJSON)
        XCTAssertEqual(v.techniques.count, 2)
        // The JSON "id" maps to techniqueID (Identifiable id is the same string).
        XCTAssertEqual(v.techniques.first?.techniqueID, "T1040")
        XCTAssertEqual(v.techniques.first?.tactic, "Credential Access")
        XCTAssertEqual(v.techniques.first?.id, "T1040")
    }

    func testDecodesDrivers() throws {
        let v = try decode(hostileJSON)
        XCTAssertEqual(v.stats.riskScore?.drivers.count, 1)
        XCTAssertEqual(v.stats.riskScore?.drivers.first?.points, 60)
    }

    func testBenignVerdictIsHonestEmpty() throws {
        let v = try decode(benignJSON)
        XCTAssertEqual(v.band, .clean)
        XCTAssertEqual(v.riskScore, 0)
        XCTAssertTrue(v.techniques.isEmpty)     // renderAttack must show nothing
        XCTAssertNil(v.focus)                   // no "look first" line
        XCTAssertEqual(v.trustColor, .green)
    }

    func testBandOrdinalAndColor() {
        XCTAssertEqual(RemoraBand("critical").ordinal, 4)
        XCTAssertTrue(RemoraBand("high").ordinal >= RemoraBand.high.ordinal)
        XCTAssertEqual(RemoraBand("nonsense"), .clean)   // unknown degrades safely
        XCTAssertEqual(RemoraBand("HIGH"), .high)        // case-insensitive
    }
}
