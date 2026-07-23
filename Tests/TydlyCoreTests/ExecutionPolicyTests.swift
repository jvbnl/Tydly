import XCTest
import TydlyCore

final class ExecutionPolicyTests: XCTestCase {
    private let automaticRule = FilingRule(
        id: "screenshots",
        name: "Screenshots",
        kind: .screenshot,
        autonomy: .auto
    )

    func testSensitiveRuleConstructorCannotCreateAutomaticRule() {
        let sensitive = FilingRule(
            id: "sensitive",
            name: "Sensitive",
            kind: .document,
            autonomy: .auto,
            isSensitive: true
        )

        XCTAssertEqual(sensitive.autonomy, .propose)
        XCTAssertFalse(
            Rules.mayAutoFile(
                rule: sensitive,
                sensitivity: .clearedForCurrentFingerprint,
                coverage: .complete,
                subscription: .active
            )
        )
    }

    func testSensitivityCombinationCanOnlyRaiseConcern() {
        XCTAssertEqual(
            SensitivityAssessment.clearedForCurrentFingerprint.combined(with: .unknown),
            .unknown
        )
        XCTAssertEqual(
            SensitivityAssessment.unknown.combined(with: .sensitive),
            .sensitive
        )
        XCTAssertEqual(
            SensitivityAssessment.sensitive.combined(with: .clearedForCurrentFingerprint),
            .sensitive
        )
    }

    func testAutomaticFilingRequiresCompleteClearedEvidenceAndPromotedRule() {
        XCTAssertTrue(
            Rules.mayAutoFile(
                rule: automaticRule,
                sensitivity: .clearedForCurrentFingerprint,
                coverage: .complete,
                subscription: .active
            )
        )

        for sensitivity in [SensitivityAssessment.unknown, .sensitive] {
            XCTAssertFalse(
                Rules.mayAutoFile(
                    rule: automaticRule,
                    sensitivity: sensitivity,
                    coverage: .complete,
                    subscription: .active
                )
            )
        }

        for coverage in EvidenceCoverage.allCases where coverage != .complete {
            XCTAssertFalse(
                Rules.mayAutoFile(
                    rule: automaticRule,
                    sensitivity: .clearedForCurrentFingerprint,
                    coverage: coverage,
                    subscription: .active
                )
            )
        }

        XCTAssertFalse(
            Rules.mayAutoFile(
                rule: nil,
                sensitivity: .clearedForCurrentFingerprint,
                coverage: .complete,
                subscription: .active
            )
        )
    }

    func testRestingBlocksAutomaticAndExplicitExecution() {
        let automatic = Rules.authorizeAutomaticExecution(
            rule: automaticRule,
            sensitivity: .clearedForCurrentFingerprint,
            coverage: .complete,
            subscription: .resting
        )
        let explicit = Rules.authorizeUserApprovedExecution(
            subscription: .resting
        )
        XCTAssertEqual(automatic.kind, .blockedWhileResting)
        XCTAssertEqual(explicit.kind, .blockedWhileResting)
    }

    func testSensitiveFilesRemainAskFirstButCanMoveAfterExplicitApproval() {
        let automatic = Rules.authorizeAutomaticExecution(
            rule: automaticRule,
            sensitivity: .sensitive,
            coverage: .complete,
            subscription: .active
        )
        let explicit = Rules.authorizeUserApprovedExecution(
            subscription: .active
        )
        XCTAssertEqual(automatic.kind, .requiresConsent(.sensitiveContent))
        XCTAssertEqual(explicit.kind, .approvedByUser)
    }

    func testModelOutputCannotImplicitlyPromoteAutonomy() {
        let proposingRule = FilingRule(
            id: "screenshots",
            name: "Screenshots",
            kind: .screenshot,
            autonomy: .propose,
            acceptsInARow: Rules.promotionThreshold
        )

        XCTAssertTrue(Rules.canOfferPromotion(proposingRule))
        let authorization = Rules.authorizeAutomaticExecution(
            rule: proposingRule,
            sensitivity: .clearedForCurrentFingerprint,
            coverage: .complete,
            subscription: .active
        )
        XCTAssertEqual(authorization.kind, .requiresConsent(.noPromotedRule))
    }

    func testPromotedRuleCapabilityCarriesExactRuleRevision() {
        let rule = FilingRule(
            id: "screenshots",
            name: "Screenshots",
            kind: .screenshot,
            autonomy: .auto,
            revision: 7
        )
        let authorization = Rules.authorizeAutomaticExecution(
            rule: rule,
            sensitivity: .clearedForCurrentFingerprint,
            coverage: .complete,
            subscription: .active
        )
        XCTAssertEqual(
            authorization.kind,
            .approvedByPromotedRule(ruleID: "screenshots", revision: 7)
        )
    }
}
