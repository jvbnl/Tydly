import XCTest
import TydlyCore

/// Each test pins one of the non-negotiable product rules (CLAUDE.md §Non-negotiable
/// product rules). If a change here goes red, a promise to the user broke.
final class RulesTests: XCTestCase {

    // MARK: Rule 2 — sensitive files can never auto-file

    func testSensitiveCategoryIsCappedAtPropose() {
        XCTAssertEqual(Rules.autonomyCeiling(isSensitive: true), .propose)
        XCTAssertEqual(Rules.autonomyCeiling(isSensitive: false), .auto)

        // No requested level can lift a sensitive category above propose.
        for requested in AutonomyLevel.allCases {
            let capped = Rules.cappedAutonomy(requested, isSensitive: true)
            XCTAssertLessThanOrEqual(capped, .propose)
        }
    }

    func testSensitiveRuleCannotBePromotedToAuto() {
        let sensitive = FilingRule(
            id: "s", name: "Sensitive files", kind: .document,
            autonomy: .propose, acceptsInARow: 999, isSensitive: true
        )
        XCTAssertFalse(Rules.canOfferPromotion(sensitive))

        // Even if a promotion is forced through, it stays capped.
        let promoted = Rules.promoting(sensitive)
        XCTAssertLessThanOrEqual(promoted.autonomy, .propose)
    }

    // MARK: Rule 4 — offered, never taken; self-demotes after 2 mistakes/week

    func testPromotionIsOnlyOfferedAtTheThreshold() {
        var rule = FilingRule(id: "r", name: "Screenshots → Atlas", kind: .screenshot,
                              autonomy: .propose, acceptsInARow: Rules.promotionThreshold - 1)
        XCTAssertFalse(Rules.canOfferPromotion(rule), "must not offer before 12 accepts")

        rule.acceptsInARow = Rules.promotionThreshold
        XCTAssertTrue(Rules.canOfferPromotion(rule), "offer unlocks exactly at 12 accepts")
    }

    func testAcceptingAPromotionReachesAuto() {
        let rule = FilingRule(id: "r", name: "Screenshots → Atlas", kind: .screenshot,
                              autonomy: .trustedRule, acceptsInARow: 12)
        XCTAssertEqual(Rules.promoting(rule).autonomy, .auto)
    }

    func testAutoRuleSelfDemotesAfterTwoMistakesInAWeek() {
        var rule = FilingRule(id: "r", name: "Screenshots → Atlas", kind: .screenshot,
                              autonomy: .auto, confidence: 0.95, mistakesThisWeek: 0)

        rule = Rules.afterMistake(rule)
        XCTAssertEqual(rule.autonomy, .auto, "one mistake does not demote")
        XCTAssertEqual(rule.mistakesThisWeek, 1)

        rule = Rules.afterMistake(rule)
        XCTAssertEqual(rule.autonomy, .propose, "two mistakes in a week demote to asking first")
    }

    func testAcceptRaisesConfidenceAndStreak() {
        let rule = FilingRule(id: "r", name: "n", kind: .screenshot, confidence: 0.5, acceptsInARow: 3)
        let next = Rules.afterAccept(rule)
        XCTAssertEqual(next.acceptsInARow, 4)
        XCTAssertGreaterThan(next.confidence, rule.confidence)
        XCTAssertEqual(next.filedCount, rule.filedCount + 1)
    }

    func testMistakeResetsStreakAndLowersConfidence() {
        let rule = FilingRule(id: "r", name: "n", kind: .screenshot,
                              autonomy: .propose, confidence: 0.8, acceptsInARow: 9)
        let next = Rules.afterMistake(rule)
        XCTAssertEqual(next.acceptsInARow, 0)
        XCTAssertLessThan(next.confidence, rule.confidence)
        XCTAssertEqual(next.undoneCount, rule.undoneCount + 1)
    }

    // MARK: Rule 10 — skipped decisions self-mute

    func testDecisionParksAfterTwoSkips() {
        let fresh = Decision(id: "d", count: 12, kind: .screenshot,
                             project: SampleData.atlas, confidence: 0.9, reason: "", skipCount: 0)
        XCTAssertFalse(Rules.shouldPark(afterSkipping: fresh), "first skip does not park")

        let skippedOnce = Decision(id: "d", count: 12, kind: .screenshot,
                                   project: SampleData.atlas, confidence: 0.9, reason: "", skipCount: 1)
        XCTAssertTrue(Rules.shouldPark(afterSkipping: skippedOnce), "second skip parks and self-mutes")
    }

    // MARK: Confidence presentation (green ≥ 85%, never a percentage)

    func testConfidenceBandThreshold() {
        XCTAssertTrue(Rules.isConfidenceHigh(0.85))
        XCTAssertTrue(Rules.isConfidenceHigh(0.92))
        XCTAssertFalse(Rules.isConfidenceHigh(0.58))
    }
}
