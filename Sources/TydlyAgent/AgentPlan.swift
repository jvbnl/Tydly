import Foundation
import TydlyCore

/// One file's place in a proposed move. Path-free by construction: the source and destination
/// are root *generation* identifiers, and resolving them to real locations happens only inside
/// `TydlyMacEngine`'s closure-scoped access.
public struct PlannedMove: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileID: String
    public let fingerprint: String
    public let sourceRootGenerationID: String
    public let destinationRootGenerationID: String
    public let evidenceBundleID: String
    public let extractorRevision: Int
    public let coverage: EvidenceCoverage
    public let sensitivity: SensitivityAssessment

    public init(
        id: String,
        fileID: String,
        fingerprint: String,
        sourceRootGenerationID: String,
        destinationRootGenerationID: String,
        evidenceBundleID: String,
        extractorRevision: Int,
        coverage: EvidenceCoverage,
        sensitivity: SensitivityAssessment
    ) {
        self.id = id
        self.fileID = fileID
        self.fingerprint = fingerprint
        self.sourceRootGenerationID = sourceRootGenerationID
        self.destinationRootGenerationID = destinationRootGenerationID
        self.evidenceBundleID = evidenceBundleID
        self.extractorRevision = extractorRevision
        self.coverage = coverage
        self.sensitivity = sensitivity
    }
}

/// An immutable proposal for one project group.
///
/// A plan carries **no execution authorization**. It is a description of what Otto would like
/// to do; only the user's explicit approval in the Finder demonstration turns it into
/// something executable, and only `TydlyCore` can issue that capability.
public struct AgentPlan: Identifiable, Equatable, Sendable {
    public let id: String
    public let projectID: String
    public let projectDisplayName: String
    public let moves: [PlannedMove]
    public let supportingEvidenceIDs: [String]
    public let source: ClassificationSource
    public let policyVersion: Int

    public init(
        id: String,
        projectID: String,
        projectDisplayName: String,
        moves: [PlannedMove],
        supportingEvidenceIDs: [String],
        source: ClassificationSource,
        policyVersion: Int
    ) {
        self.id = id
        self.projectID = projectID
        self.projectDisplayName = projectDisplayName
        self.moves = moves
        self.supportingEvidenceIDs = supportingEvidenceIDs
        self.source = source
        self.policyVersion = policyVersion
    }

    public var fileCount: Int { moves.count }

    /// True when any file in the group is sensitive or incompletely understood. Such a group
    /// is still proposed — Rule 2 makes it permanently ask-first, not hidden — but it can
    /// never be satisfied by a promoted rule.
    public var isPermanentlyAskFirst: Bool {
        moves.contains { $0.sensitivity != .clearedForCurrentFingerprint || $0.coverage != .complete }
    }

    /// The canonical, deterministic serialization that AH-77 will hash into the immutable
    /// demonstration digest. Everything that could change what actually happens on disk is
    /// included; nothing that could leak a path or file content is.
    ///
    /// Ordering is explicit rather than incidental so that the same plan always produces the
    /// same payload regardless of how the moves were collected.
    public var canonicalDigestPayload: String {
        let unit = "\u{1F}"
        let record = "\u{1E}"

        let header = [
            "tydly.plan.v1",
            projectID,
            String(policyVersion),
            source.rawValue
        ].joined(separator: unit)

        let moveRecords = moves
            .map { move in
                [
                    move.fileID,
                    move.fingerprint,
                    move.sourceRootGenerationID,
                    move.destinationRootGenerationID,
                    move.evidenceBundleID,
                    String(move.extractorRevision),
                    move.coverage.rawValue,
                    move.sensitivity.rawValue
                ].joined(separator: unit)
            }
            .sorted()

        return ([header] + moveRecords).joined(separator: record)
    }
}

/// Why the agent produced no plan for a group of evidence.
public enum AgentAbstention: Equatable, Sendable {
    case noEvidence
    case noCandidates
    case classifierAbstained
    case watchOnly(WatchOnlyReason)
}

/// The result of reasoning over one sweep's evidence.
public enum AgentPlanOutcome: Equatable, Sendable {
    case plan(AgentPlan)

    /// The agent identified a project but the user has never authorized a destination for it.
    /// The UI must ask for a folder through Powerbox, persist that destination generation, and
    /// only then rebuild and demonstrate the plan. The agent must never invent a path.
    case needsDestination(projectID: String, displayName: String, fileIDs: [String])

    case abstained(AgentAbstention)
}
