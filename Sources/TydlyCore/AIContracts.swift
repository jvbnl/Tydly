import Foundation

/// How completely the trusted extraction pipeline inspected a file for the current
/// fingerprint. Anything other than `complete` is ineligible for automatic filing.
public enum EvidenceCoverage: String, CaseIterable, Equatable, Sendable {
    case complete
    case partial
    case unsupported
    case failed
}

/// A monotonic privacy lattice. A model may raise concern, but it can never clear a
/// deterministic sensitive or unknown assessment.
public enum SensitivityAssessment: String, CaseIterable, Equatable, Sendable {
    case clearedForCurrentFingerprint
    case unknown
    case sensitive

    public func combined(with other: SensitivityAssessment) -> SensitivityAssessment {
        if self == .sensitive || other == .sensitive {
            return .sensitive
        }
        if self == .unknown || other == .unknown {
            return .unknown
        }
        return .clearedForCurrentFingerprint
    }
}

/// Typed provenance for one bounded fact. `value` is untrusted local data and must never be
/// interpolated into model instructions, logs, or UI without validation and localization.
public enum EvidenceKind: String, CaseIterable, Equatable, Sendable {
    case filenameToken
    case fileMetadata
    case spotlightMetadata
    case temporalContext
    case acceptedExample
    case semanticSimilarity
    case documentSignal
    case sensitivitySignal
}

public struct EvidenceFact: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: EvidenceKind
    public let value: String

    public init(id: String, kind: EvidenceKind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

/// A project that deterministic retrieval has already resolved inside a user-approved root.
/// The AI engine can select only one of these opaque IDs; it never receives a writable path.
public struct ProjectCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let supportingEvidenceIDs: [String]

    public init(id: String, displayName: String, supportingEvidenceIDs: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.supportingEvidenceIDs = supportingEvidenceIDs
    }
}

/// A data-minimized, path-free request for optional semantic reranking.
public struct ClassificationRequest: Equatable, Sendable {
    public let fileID: String
    public let fingerprint: String
    public let kindHint: FileKind?
    public let coverage: EvidenceCoverage
    public let sensitivity: SensitivityAssessment
    public let evidence: [EvidenceFact]
    public let candidates: [ProjectCandidate]

    public init(
        fileID: String,
        fingerprint: String,
        kindHint: FileKind? = nil,
        coverage: EvidenceCoverage,
        sensitivity: SensitivityAssessment,
        evidence: [EvidenceFact],
        candidates: [ProjectCandidate]
    ) {
        self.fileID = fileID
        self.fingerprint = fingerprint
        self.kindHint = kindHint
        self.coverage = coverage
        self.sensitivity = sensitivity
        self.evidence = evidence
        self.candidates = candidates
    }
}

public enum ClassificationSource: String, Equatable, Sendable {
    case deterministic
    case foundationModel
}

/// Validated advisory output. Confidence and execution permission deliberately do not appear
/// here: calibrated deterministic code and `Rules` own those decisions.
public struct ClassificationResult: Equatable, Sendable {
    public let projectID: String?
    public let supportingEvidenceIDs: [String]
    public let sensitivity: SensitivityAssessment
    public let abstained: Bool
    public let source: ClassificationSource

    public init(
        projectID: String?,
        supportingEvidenceIDs: [String],
        sensitivity: SensitivityAssessment,
        abstained: Bool,
        source: ClassificationSource
    ) {
        self.projectID = projectID
        self.supportingEvidenceIDs = supportingEvidenceIDs
        self.sensitivity = sensitivity
        self.abstained = abstained
        self.source = source
    }

    public static func abstaining(
        sensitivity: SensitivityAssessment,
        source: ClassificationSource
    ) -> ClassificationResult {
        ClassificationResult(
            projectID: nil,
            supportingEvidenceIDs: [],
            sensitivity: sensitivity,
            abstained: true,
            source: source
        )
    }
}

/// The only AI capability exposed to orchestration. Implementations receive no filesystem,
/// journal, rule-mutation, or tool interface.
public protocol LocalClassificationEngine: Sendable {
    func classify(_ request: ClassificationRequest) async throws -> ClassificationResult
}
