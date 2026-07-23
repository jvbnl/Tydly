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

public enum ExecutionAuthorizationKind: Equatable, Sendable {
    case approvedByUser
    case approvedByPromotedRule(ruleID: String, revision: Int)
    case requiresConsent(AutomaticFilingDenial)
    case blockedWhileResting
}

/// Opaque capability issued only by the deterministic policy gate. Model output and decoded
/// data cannot directly construct an authorization value.
public struct ExecutionAuthorization: Equatable, Sendable {
    public let kind: ExecutionAuthorizationKind

    fileprivate init(kind: ExecutionAuthorizationKind) {
        self.kind = kind
    }
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

    static func authorizeAutomaticExecution(
        rule: FilingRule?,
        sensitivity: SensitivityAssessment,
        coverage: EvidenceCoverage,
        subscription: Subscription
    ) -> ExecutionAuthorization {
        if subscription == .resting {
            return ExecutionAuthorization(kind: .blockedWhileResting)
        }
        if let denial = automaticFilingDenial(
            rule: rule,
            sensitivity: sensitivity,
            coverage: coverage,
            subscription: subscription
        ) {
            return ExecutionAuthorization(kind: .requiresConsent(denial))
        }
        guard let rule else {
            return ExecutionAuthorization(kind: .requiresConsent(.noPromotedRule))
        }
        return ExecutionAuthorization(
            kind: .approvedByPromotedRule(ruleID: rule.id, revision: rule.revision)
        )
    }

    /// Package-scoped capability issuance for the Finder demonstration's explicit approval
    /// action. It is intentionally unavailable to external clients and decoded/model data.
    /// Sensitive files remain ask-first; resting remains watch-only.
    package static func authorizeUserApprovedExecution(
        subscription: Subscription
    ) -> ExecutionAuthorization {
        if subscription == .resting {
            return ExecutionAuthorization(kind: .blockedWhileResting)
        }
        return ExecutionAuthorization(kind: .approvedByUser)
    }
}
