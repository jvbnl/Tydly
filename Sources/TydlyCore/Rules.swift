import Foundation

/// The non-negotiable product rules, encoded as pure logic so they are enforced in the
/// model — not merely honored by the UI. Unit-tested in `TydlyCoreTests`.
///
/// Reference: CLAUDE.md §Non-negotiable product rules, README §State Management.
public enum Rules {

    // MARK: Thresholds

    /// Accepts-in-a-row before Otto *offers* to promote a category to a rule.
    /// Rule 4: autonomy is offered, never taken — reaching this only unlocks the offer.
    public static let promotionThreshold = 12

    /// Mistakes within a rolling week that force an auto rule back down to asking.
    /// Rule 4: rules self-demote after 2 mistakes/week.
    public static let mistakesBeforeDemotion = 2

    /// Times a decision may be skipped before it parks and self-mutes (Rule 10).
    public static let skipsBeforeParking = 2

    /// The confidence at/above which the bar reads green rather than amber (DESIGN.md).
    public static let confidenceHighThreshold = 0.85

    // MARK: Rule 2 — sensitive files can never auto-file

    /// The highest autonomy a category may ever reach. Sensitive categories are
    /// permanently capped at `.propose` (ask-first) — no path, offer, or bug can lift it.
    public static func autonomyCeiling(isSensitive: Bool) -> AutonomyLevel {
        isSensitive ? .propose : .auto
    }

    /// Clamp any requested autonomy to the ceiling for the category.
    public static func cappedAutonomy(_ requested: AutonomyLevel, isSensitive: Bool) -> AutonomyLevel {
        min(requested, autonomyCeiling(isSensitive: isSensitive))
    }

    // MARK: Rule 4 — offered, never taken; self-demotes

    /// Whether Otto may *offer* to turn this category into an auto rule. Never promotes
    /// on its own, and never for sensitive categories.
    public static func canOfferPromotion(_ rule: FilingRule) -> Bool {
        !rule.isSensitive
            && rule.autonomy < .auto
            && rule.acceptsInARow >= promotionThreshold
    }

    /// Apply the user *accepting* the promotion offer. Clamps to the sensitive ceiling,
    /// so accepting a promotion on a sensitive rule is a no-op above `.propose`.
    public static func promoting(_ rule: FilingRule) -> FilingRule {
        var next = rule
        next.autonomy = cappedAutonomy(.auto, isSensitive: rule.isSensitive)
        next.revision += 1
        return next
    }

    /// Record an accepted proposal: confidence rises, streak grows.
    public static func afterAccept(_ rule: FilingRule) -> FilingRule {
        var next = rule
        next.acceptsInARow += 1
        next.filedCount += 1
        next.confidence = min(1.0, rule.confidence + 0.04)
        next.revision += 1
        return next
    }

    /// Record a mistake (an undo, or the user moving a filed file back). Confidence
    /// falls, the accept streak resets, and an auto rule that reaches the weekly mistake
    /// limit self-demotes to asking first.
    public static func afterMistake(_ rule: FilingRule) -> FilingRule {
        var next = rule
        next.mistakesThisWeek += 1
        next.acceptsInARow = 0
        next.undoneCount += 1
        next.confidence = max(0.0, rule.confidence - 0.15)
        if next.autonomy >= .trustedRule && next.mistakesThisWeek >= mistakesBeforeDemotion {
            next.autonomy = .propose
            next.mistakesThisWeek = 0 // demotion consumes the week's tally
        }
        next.revision += 1
        return next
    }

    /// Reset the rolling weekly mistake tally (call at the week boundary).
    public static func resettingWeek(_ rule: FilingRule) -> FilingRule {
        var next = rule
        next.mistakesThisWeek = 0
        next.revision += 1
        return next
    }

    // MARK: Rule 10 — skipped decisions self-mute

    /// Whether skipping this decision one more time should park it (park → re-ask Friday
    /// once → silence).
    public static func shouldPark(afterSkipping decision: Decision) -> Bool {
        (decision.skipCount + 1) >= skipsBeforeParking
    }

    // MARK: Presentation-adjacent helpers (still pure)

    /// Green vs amber confidence bar. Never rendered as a percentage.
    public static func isConfidenceHigh(_ confidence: Double) -> Bool {
        confidence >= confidenceHighThreshold
    }
}
