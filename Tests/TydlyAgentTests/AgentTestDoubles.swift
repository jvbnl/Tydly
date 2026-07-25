import Foundation
import TydlyAgent
import TydlyCore

/// Programmable memory. An actor so it satisfies `Sendable` without unchecked escapes.
actor StubMemory: AgentMemoryStore {
    private let projects: [ProjectMemory]
    private let candidatesByFileID: [String: [ProjectCandidate]]
    private(set) var recorded: [AgentOutcome] = []

    init(projects: [ProjectMemory], candidatesByFileID: [String: [ProjectCandidate]]) {
        self.projects = projects
        self.candidatesByFileID = candidatesByFileID
    }

    func knownProjects() async throws -> [ProjectMemory] { projects }

    func candidates(for bundle: EvidenceBundleReference) async throws -> [ProjectCandidate] {
        candidatesByFileID[bundle.fileID] ?? []
    }

    func corrections(for fileID: String) async throws -> [MemoryCorrection] { [] }

    func record(_ outcome: AgentOutcome) async throws {
        recorded.append(outcome)
    }

    func recordedOutcomes() -> [AgentOutcome] { recorded }
}

/// Programmable classifier. Also counts invocations so the "one model request at a time"
/// expectation can be asserted.
actor StubClassifier: LocalClassificationEngine {
    private let resultsByFileID: [String: ClassificationResult]
    private let fallback: ClassificationResult
    private(set) var requestCount = 0
    private(set) var maxConcurrent = 0
    private var inFlight = 0

    init(
        resultsByFileID: [String: ClassificationResult] = [:],
        fallback: ClassificationResult = .abstaining(
            sensitivity: .unknown,
            source: .deterministic
        )
    ) {
        self.resultsByFileID = resultsByFileID
        self.fallback = fallback
    }

    func classify(_ request: ClassificationRequest) async throws -> ClassificationResult {
        inFlight += 1
        maxConcurrent = max(maxConcurrent, inFlight)
        requestCount += 1
        defer { inFlight -= 1 }
        return resultsByFileID[request.fileID] ?? fallback
    }

    func observedRequestCount() -> Int { requestCount }
    func observedMaxConcurrent() -> Int { maxConcurrent }
}

actor StubConditions: SystemConditionsProviding {
    private let conditions: SystemConditions

    init(_ conditions: SystemConditions = .idle) {
        self.conditions = conditions
    }

    func currentConditions() async -> SystemConditions { conditions }
}

// MARK: - Fixtures

enum Fixture {
    static func bundle(
        fileID: String,
        coverage: EvidenceCoverage = .complete,
        sensitivity: SensitivityAssessment = .clearedForCurrentFingerprint,
        rootGenerationID: String = "root-desktop-g1"
    ) -> EvidenceBundleReference {
        EvidenceBundleReference(
            id: "bundle-\(fileID)",
            fileID: fileID,
            fingerprint: "fp-\(fileID)",
            rootGenerationID: rootGenerationID,
            kindHint: .screenshot,
            coverage: coverage,
            sensitivity: sensitivity,
            extractorRevision: 3,
            facts: [EvidenceFact(id: "e-\(fileID)", kind: .filenameToken, value: "atlas")]
        )
    }

    static func selecting(
        _ projectID: String,
        sensitivity: SensitivityAssessment = .clearedForCurrentFingerprint,
        source: ClassificationSource = .foundationModel,
        evidenceIDs: [String] = []
    ) -> ClassificationResult {
        ClassificationResult(
            projectID: projectID,
            supportingEvidenceIDs: evidenceIDs,
            sensitivity: sensitivity,
            abstained: false,
            source: source
        )
    }

    static let atlasCandidate = ProjectCandidate(id: "atlas", displayName: "Atlas")

    static func atlas(destination: String? = "dest-atlas-g1") -> ProjectMemory {
        ProjectMemory(
            id: "atlas",
            displayName: "Atlas",
            destinationGenerationID: destination
        )
    }
}
