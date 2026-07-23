import Foundation

/// Why a proposal cannot execute automatically. These are stable policy keys, not
/// user-facing copy.
public enum AutomaticFilingDenial: Equatable, Sendable {
    case resting
    case sensitiveRule
    case sensitiveContent
    case unknownSensitivity
    case incompleteEvidence(EvidenceCoverage)
    case noPromotedRule
}

/// The only two paths that may authorize a move. Operational validation and the durable
/// journal still run after authorization and may stop execution.
public enum ExecutionAuthorization: Equatable, Sendable {
    case approvedByUser
    case approvedByPromotedRule
    case requiresConsent(AutomaticFilingDenial)
    case blockedWhileResting
}

public extension Rules {
    /// Returns the first policy reason that prevents automatic filing. A nil result means
    /// policy allows the operation to continue to operational validation; it does not mean
    /// the filesystem move itself is safe yet.
    static func automaticFilingDenial(
        rule: FilingRule?,
        sensitivity: SensitivityAssessment,
        coverage: EvidenceCoverage,
        subscription: Subscription
    ) -> AutomaticFilingDenial? {
        if subscription == .resting {
            return .resting
        }
        if rule?.isSensitive == true {
            return .sensitiveRule
        }
        switch sensitivity {
        case .sensitive:
            return .sensitiveContent
        case .unknown:
            return .unknownSensitivity
        case .clearedForCurrentFingerprint:
            break
        }
        guard coverage == .complete else {
            return .incompleteEvidence(coverage)
        }
        guard let rule, rule.autonomy == .auto else {
            return .noPromotedRule
        }
        return nil
    }

    static func mayAutoFile(
        rule: FilingRule?,
        sensitivity: SensitivityAssessment,
        coverage: EvidenceCoverage,
        subscription: Subscription
    ) -> Bool {
        automaticFilingDenial(
            rule: rule,
            sensitivity: sensitivity,
            coverage: coverage,
            subscription: subscription
        ) == nil
    }

    /// Explicit approval authorizes ask-first items, including sensitive files. Sensitive
    /// status is never converted into an automatic rule. Resting remains watch-only even if
    /// stale UI tries to submit an approval.
    static func authorizeExecution(
        rule: FilingRule?,
        sensitivity: SensitivityAssessment,
        coverage: EvidenceCoverage,
        subscription: Subscription,
        userApproved: Bool
    ) -> ExecutionAuthorization {
        if subscription == .resting {
            return .blockedWhileResting
        }
        if userApproved {
            return .approvedByUser
        }
        if let denial = automaticFilingDenial(
            rule: rule,
            sensitivity: sensitivity,
            coverage: coverage,
            subscription: subscription
        ) {
            return .requiresConsent(denial)
        }
        return .approvedByPromotedRule
    }
}
