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
        XCTAssertEqual(
            Rules.authorizeExecution(
                rule: automaticRule,
                sensitivity: .clearedForCurrentFingerprint,
                coverage: .complete,
                subscription: .resting,
                userApproved: false
            ),
            .blockedWhileResting
        )
        XCTAssertEqual(
            Rules.authorizeExecution(
                rule: automaticRule,
                sensitivity: .clearedForCurrentFingerprint,
                coverage: .complete,
                subscription: .resting,
                userApproved: true
            ),
            .blockedWhileResting
        )
    }

    func testSensitiveFilesRemainAskFirstButCanMoveAfterExplicitApproval() {
        XCTAssertEqual(
            Rules.authorizeExecution(
                rule: automaticRule,
                sensitivity: .sensitive,
                coverage: .complete,
                subscription: .active,
                userApproved: false
            ),
            .requiresConsent(.sensitiveContent)
        )
        XCTAssertEqual(
            Rules.authorizeExecution(
                rule: automaticRule,
                sensitivity: .sensitive,
                coverage: .complete,
                subscription: .active,
                userApproved: true
            ),
            .approvedByUser
        )
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
        XCTAssertEqual(
            Rules.authorizeExecution(
                rule: proposingRule,
                sensitivity: .clearedForCurrentFingerprint,
                coverage: .complete,
                subscription: .active,
                userApproved: false
            ),
            .requiresConsent(.noPromotedRule)
        )
    }
}
