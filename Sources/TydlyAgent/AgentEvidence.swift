import Foundation
import TydlyCore

/// A typed, path-free reference to one file's evidence, produced by the isolated read-only
/// extractor and consumed by the agent.
///
/// Deliberately absent, and never to be added: absolute paths, bookmark data, raw extracted
/// text, OCR output, rendered pages, and thumbnails. The agent orchestrates *references and
/// typed facts*; source content never enters this layer, and never reaches persistence.
///
/// `rootGenerationID` pins the file to the exact authorized root generation it was seen in.
/// A plan built from a stale generation must not execute — `TydlyMacEngine` revalidates, but
/// carrying the ID here is what makes that check possible at all.
public struct EvidenceBundleReference: Identifiable, Equatable, Sendable {
    public let id: String
    public let fileID: String
    public let fingerprint: String
    public let rootGenerationID: String
    public let kindHint: FileKind?
    public let coverage: EvidenceCoverage
    public let sensitivity: SensitivityAssessment
    public let extractorRevision: Int
    public let facts: [EvidenceFact]

    public init(
        id: String,
        fileID: String,
        fingerprint: String,
        rootGenerationID: String,
        kindHint: FileKind? = nil,
        coverage: EvidenceCoverage,
        sensitivity: SensitivityAssessment,
        extractorRevision: Int,
        facts: [EvidenceFact] = []
    ) {
        self.id = id
        self.fileID = fileID
        self.fingerprint = fingerprint
        self.rootGenerationID = rootGenerationID
        self.kindHint = kindHint
        self.coverage = coverage
        self.sensitivity = sensitivity
        self.extractorRevision = extractorRevision
        self.facts = facts
    }

    /// The bounded, path-free request handed to the advisory classifier.
    ///
    /// Note that a `sensitive` bundle is still classified and still proposed: Rule 2 makes
    /// sensitive files permanently *ask-first*, not invisible. What sensitivity forbids is
    /// automatic execution, and that is enforced by `Rules.automaticFilingDenial`.
    public func classificationRequest(
        candidates: [ProjectCandidate]
    ) -> ClassificationRequest {
        ClassificationRequest(
            fileID: fileID,
            fingerprint: fingerprint,
            kindHint: kindHint,
            coverage: coverage,
            sensitivity: sensitivity,
            evidence: facts,
            candidates: candidates
        )
    }
}
