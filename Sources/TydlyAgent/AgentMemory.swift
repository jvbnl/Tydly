import Foundation
import TydlyCore

/// A project Otto already knows about, together with the destination the user authorized for
/// it. `destinationGenerationID` is nil until the user has chosen a folder through Powerbox —
/// the agent may propose a *new project label*, but it may never invent a destination.
public struct ProjectMemory: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let destinationGenerationID: String?
    public let aliases: [String]
    public let acceptedExampleCount: Int
    public let correctedExampleCount: Int

    public init(
        id: String,
        displayName: String,
        destinationGenerationID: String? = nil,
        aliases: [String] = [],
        acceptedExampleCount: Int = 0,
        correctedExampleCount: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.destinationGenerationID = destinationGenerationID
        self.aliases = aliases
        self.acceptedExampleCount = acceptedExampleCount
        self.correctedExampleCount = correctedExampleCount
    }

    public var hasAuthorizedDestination: Bool { destinationGenerationID != nil }

    public var candidate: ProjectCandidate {
        ProjectCandidate(id: id, displayName: displayName)
    }
}

/// A user correction between two files. `mustLink` means "these belong together";
/// `cannotLink` means "never group these again".
public enum CorrectionRelation: String, CaseIterable, Equatable, Sendable {
    case mustLink
    case cannotLink
}

public struct MemoryCorrection: Equatable, Sendable {
    public let relation: CorrectionRelation
    public let fileID: String
    public let otherFileID: String

    public init(relation: CorrectionRelation, fileID: String, otherFileID: String) {
        self.relation = relation
        self.fileID = fileID
        self.otherFileID = otherFileID
    }
}

/// How a proposal actually ended. `AI_ENGINE.md` §Learning from feedback: a skip is a
/// deferral, not a class label, and silence after an automatic move is censored data — so
/// neither is recorded as a positive.
public enum AgentOutcomeKind: String, CaseIterable, Equatable, Sendable {
    case accepted
    case correctedToOtherProject
    case undoneAsWrongPlace
    case skipped
    case parked
}

/// One learning record. Carries the revisions the prediction was made under so that a model
/// or extractor upgrade can invalidate stale learning rather than silently inheriting it.
public struct AgentOutcome: Equatable, Sendable {
    public let fileID: String
    public let fingerprint: String
    public let predictedProjectID: String?
    public let actualProjectID: String?
    public let kind: AgentOutcomeKind
    public let source: ClassificationSource
    public let extractorRevision: Int
    public let policyVersion: Int

    public init(
        fileID: String,
        fingerprint: String,
        predictedProjectID: String?,
        actualProjectID: String?,
        kind: AgentOutcomeKind,
        source: ClassificationSource,
        extractorRevision: Int,
        policyVersion: Int
    ) {
        self.fileID = fileID
        self.fingerprint = fingerprint
        self.predictedProjectID = predictedProjectID
        self.actualProjectID = actualProjectID
        self.kind = kind
        self.source = source
        self.extractorRevision = extractorRevision
        self.policyVersion = policyVersion
    }
}

/// Encrypted, data-minimized agent memory.
///
/// Implementations live in `TydlyPersistence`; this target deliberately depends on the
/// protocol only, so the agent stays pure and testable. Implementations must persist **no**
/// source text, OCR output, or model transcripts — only opaque IDs, typed facts, bounded
/// exemplars, and outcomes.
public protocol AgentMemoryStore: Sendable {
    func knownProjects() async throws -> [ProjectMemory]

    /// Deterministic candidate retrieval, run *before* any model reasoning. Returns a small
    /// allowlist; the classifier can only choose from within it.
    func candidates(for bundle: EvidenceBundleReference) async throws -> [ProjectCandidate]

    func corrections(for fileID: String) async throws -> [MemoryCorrection]

    func record(_ outcome: AgentOutcome) async throws
}
