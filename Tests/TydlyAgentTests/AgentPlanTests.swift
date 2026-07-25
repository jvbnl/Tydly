import XCTest
import TydlyAgent
import TydlyCore

final class AgentPlanTests: XCTestCase {
    private func move(
        fileID: String,
        destination: String = "dest-atlas-g1",
        coverage: EvidenceCoverage = .complete,
        sensitivity: SensitivityAssessment = .clearedForCurrentFingerprint
    ) -> PlannedMove {
        PlannedMove(
            id: "bundle-\(fileID)",
            fileID: fileID,
            fingerprint: "fp-\(fileID)",
            sourceRootGenerationID: "root-desktop-g1",
            destinationRootGenerationID: destination,
            evidenceBundleID: "bundle-\(fileID)",
            extractorRevision: 3,
            coverage: coverage,
            sensitivity: sensitivity
        )
    }

    private func plan(
        id: String = "plan-1",
        moves: [PlannedMove],
        policyVersion: Int = 1,
        source: ClassificationSource = .foundationModel
    ) -> AgentPlan {
        AgentPlan(
            id: id,
            projectID: "atlas",
            projectDisplayName: "Atlas",
            moves: moves,
            supportingEvidenceIDs: ["e1"],
            source: source,
            policyVersion: policyVersion
        )
    }

    // MARK: - Digest

    func testDigestPayloadIsStableAcrossMoveOrdering() {
        let a = plan(moves: [move(fileID: "f1"), move(fileID: "f2")])
        let b = plan(id: "plan-2", moves: [move(fileID: "f2"), move(fileID: "f1")])

        XCTAssertEqual(a.canonicalDigestPayload, b.canonicalDigestPayload)
    }

    func testDigestPayloadChangesWithDestination() {
        let a = plan(moves: [move(fileID: "f1")])
        let b = plan(moves: [move(fileID: "f1", destination: "dest-other-g1")])

        XCTAssertNotEqual(a.canonicalDigestPayload, b.canonicalDigestPayload)
    }

    func testDigestPayloadChangesWithFingerprintCoverageAndSensitivity() {
        let base = plan(moves: [move(fileID: "f1")])

        XCTAssertNotEqual(
            base.canonicalDigestPayload,
            plan(moves: [move(fileID: "f1", coverage: .partial)]).canonicalDigestPayload
        )
        XCTAssertNotEqual(
            base.canonicalDigestPayload,
            plan(moves: [move(fileID: "f1", sensitivity: .sensitive)]).canonicalDigestPayload
        )
        XCTAssertNotEqual(
            base.canonicalDigestPayload,
            plan(moves: [move(fileID: "f2")]).canonicalDigestPayload
        )
    }

    func testDigestPayloadChangesWithPolicyVersion() {
        XCTAssertNotEqual(
            plan(moves: [move(fileID: "f1")], policyVersion: 1).canonicalDigestPayload,
            plan(moves: [move(fileID: "f1")], policyVersion: 2).canonicalDigestPayload
        )
    }

    func testDigestPayloadCarriesNoPaths() {
        let payload = plan(moves: [move(fileID: "f1")]).canonicalDigestPayload

        XCTAssertFalse(payload.contains("/"))
        XCTAssertFalse(payload.lowercased().contains("users"))
        XCTAssertFalse(payload.lowercased().contains("desktop/"))
    }

    // MARK: - Ask-first

    func testCleanCompleteGroupIsNotPermanentlyAskFirst() {
        XCTAssertFalse(plan(moves: [move(fileID: "f1"), move(fileID: "f2")]).isPermanentlyAskFirst)
    }

    func testOneSensitiveMemberMakesTheWholeGroupAskFirst() {
        let mixed = plan(moves: [
            move(fileID: "f1"),
            move(fileID: "f2", sensitivity: .sensitive)
        ])
        XCTAssertTrue(mixed.isPermanentlyAskFirst)
    }

    func testIncompleteCoverageMakesTheGroupAskFirst() {
        for coverage in [EvidenceCoverage.partial, .unsupported, .failed] {
            XCTAssertTrue(
                plan(moves: [move(fileID: "f1", coverage: coverage)]).isPermanentlyAskFirst,
                "\(coverage) coverage must stay ask-first"
            )
        }
    }

    func testUnknownSensitivityMakesTheGroupAskFirst() {
        XCTAssertTrue(
            plan(moves: [move(fileID: "f1", sensitivity: .unknown)]).isPermanentlyAskFirst
        )
    }
}
