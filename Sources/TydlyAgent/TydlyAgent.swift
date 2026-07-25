import Foundation
import TydlyCore

/// Identifies one sweep. Handed out by `beginSweep` and required by every subsequent call, so
/// a late reply from an abandoned sweep can never write into a newer one.
public struct SweepToken: Hashable, Sendable {
    public let id: UUID

    fileprivate init(id: UUID) {
        self.id = id
    }
}

public enum SweepRefusal: Error, Equatable, Sendable {
    /// One sweep at a time. A second request is refused, never queued.
    case alreadySweeping
    case watchOnly(WatchOnlyReason)
    /// The Mac is busy, hot, or on Low Power Mode. Try again when it is idle.
    case deferred(SystemPressure)
}

public enum AgentError: Error, Equatable, Sendable {
    case sweepNotActive
    case sweepCancelled
}

/// Otto's orchestration loop: perceive → remember → reason → plan → demonstrate → act → learn.
///
/// This actor owns the *reason* and *plan* stages and coordinates the rest. Three boundaries
/// are structural and must stay that way:
///
/// - **It never moves a file.** No filesystem API is reachable from this target.
/// - **It never issues an `ExecutionAuthorization`.** Only `TydlyCore.Rules` does, and only
///   after the user's explicit approval or an explicitly promoted rule.
/// - **It never sees a path.** Evidence and plans carry opaque IDs and root generation IDs;
///   `TydlyMacEngine` is the only place a real location exists, inside scoped access.
///
/// The concrete `LocalClassificationEngine` (`TydlyAI`) is injected by the app layer rather
/// than depended on directly, which keeps this target pure Foundation and lets every path be
/// tested without Apple Intelligence.
public actor TydlyAgent {
    private let memory: any AgentMemoryStore
    private let classifier: any LocalClassificationEngine
    private let conditions: any SystemConditionsProviding
    private let policyVersion: Int

    private var activeSweep: SweepToken?
    private var cancellationRequested = false

    public init(
        memory: any AgentMemoryStore,
        classifier: any LocalClassificationEngine,
        conditions: any SystemConditionsProviding,
        policyVersion: Int = 1
    ) {
        self.memory = memory
        self.classifier = classifier
        self.conditions = conditions
        self.policyVersion = policyVersion
    }

    public var isSweeping: Bool { activeSweep != nil }

    // MARK: - Sweep lifecycle

    /// Admits at most one sweep at a time, and only when posture and system pressure allow it.
    public func beginSweep(posture: AgentPosture) async -> Result<SweepToken, SweepRefusal> {
        guard activeSweep == nil else {
            return .failure(.alreadySweeping)
        }
        if let reason = posture.watchOnlyReason {
            return .failure(.watchOnly(reason))
        }
        let reading = await conditions.currentConditions()
        if let pressure = reading.deferringPressure {
            return .failure(.deferred(pressure))
        }

        let token = SweepToken(id: UUID())
        activeSweep = token
        cancellationRequested = false
        return .success(token)
    }

    /// Ends the sweep if `token` is still the active one. A stale token is ignored, so a
    /// cancelled sweep finishing late cannot end its successor.
    public func endSweep(_ token: SweepToken) {
        guard activeSweep == token else { return }
        activeSweep = nil
        cancellationRequested = false
    }

    /// Requests cancellation. The in-flight `reason(about:)` call stops at its next checkpoint
    /// and throws `AgentError.sweepCancelled`, leaving the filesystem and ledger untouched —
    /// there is nothing to roll back, because reasoning mutates neither.
    public func cancelActiveSweep() {
        guard activeSweep != nil else { return }
        cancellationRequested = true
    }

    // MARK: - Reasoning

    /// Turns one sweep's evidence into proposals, grouped by project.
    ///
    /// Model requests are issued one at a time (`AI_ENGINE.md` §Efficiency policy) — the actor
    /// serializes them by construction.
    public func reason(
        about bundles: [EvidenceBundleReference],
        posture: AgentPosture,
        token: SweepToken
    ) async throws -> [AgentPlanOutcome] {
        guard activeSweep == token else {
            throw AgentError.sweepNotActive
        }
        if let reason = posture.watchOnlyReason {
            return [.abstained(.watchOnly(reason))]
        }
        guard !bundles.isEmpty else {
            return [.abstained(.noEvidence)]
        }

        let projects = try await memory.knownProjects()
        // Tolerant of a duplicate ID rather than trapping: a corrupt memory row must not be
        // able to crash a sweep.
        let projectsByID = Dictionary(
            projects.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var groupOrder: [String] = []
        var grouped: [String: [PlannedMove]] = [:]
        var evidenceByProject: [String: [String]] = [:]
        var sourceByProject: [String: ClassificationSource] = [:]
        var sawUnassigned = false
        var sawMissingCandidates = false
        // Per-sweep scratch, deliberately local: if this call throws (cancellation), nothing
        // survives to contaminate the next sweep.
        var unauthorizedOrder: [String] = []
        var unauthorizedNames: [String: String] = [:]
        var unauthorizedFiles: [String: [String]] = [:]

        for bundle in bundles {
            try checkCancellation()

            let candidates = try await memory.candidates(for: bundle)
            guard !candidates.isEmpty else {
                sawMissingCandidates = true
                continue
            }

            let result = try await classifier.classify(
                bundle.classificationRequest(candidates: candidates)
            )

            // Defense in depth: TydlyAI already validates against the allowlist, but the agent
            // re-checks the identifier it actually sent. An unrecognised ID is an abstention,
            // never a destination.
            let allowedIDs = Set(candidates.map(\.id))
            guard
                !result.abstained,
                let projectID = result.projectID,
                allowedIDs.contains(projectID)
            else {
                sawUnassigned = true
                continue
            }

            guard let project = projectsByID[projectID] else {
                sawUnassigned = true
                continue
            }

            // Monotonic lattice: the model may raise sensitivity, never clear it.
            let sensitivity = bundle.sensitivity.combined(with: result.sensitivity)

            guard let destinationID = project.destinationGenerationID else {
                // Grouped so the UI can ask for one folder, once, for all of these files.
                if unauthorizedFiles[projectID] == nil {
                    unauthorizedOrder.append(projectID)
                    unauthorizedNames[projectID] = project.displayName
                    unauthorizedFiles[projectID] = []
                }
                unauthorizedFiles[projectID]?.append(bundle.fileID)
                continue
            }

            let move = PlannedMove(
                id: bundle.id,
                fileID: bundle.fileID,
                fingerprint: bundle.fingerprint,
                sourceRootGenerationID: bundle.rootGenerationID,
                destinationRootGenerationID: destinationID,
                evidenceBundleID: bundle.id,
                extractorRevision: bundle.extractorRevision,
                coverage: bundle.coverage,
                sensitivity: sensitivity
            )

            if grouped[projectID] == nil {
                groupOrder.append(projectID)
                grouped[projectID] = []
            }
            grouped[projectID]?.append(move)
            evidenceByProject[projectID, default: []]
                .append(contentsOf: result.supportingEvidenceIDs)
            // A group is only as deterministic as its least deterministic member.
            if sourceByProject[projectID] != .foundationModel {
                sourceByProject[projectID] = result.source
            }
        }

        try checkCancellation()

        var outcomes: [AgentPlanOutcome] = groupOrder.compactMap { projectID -> AgentPlanOutcome? in
            guard
                let moves = grouped[projectID],
                let project = projectsByID[projectID]
            else {
                return nil
            }
            let plan = AgentPlan(
                id: "\(token.id.uuidString):\(projectID)",
                projectID: projectID,
                projectDisplayName: project.displayName,
                moves: moves,
                supportingEvidenceIDs: Array(Set(evidenceByProject[projectID] ?? [])).sorted(),
                source: sourceByProject[projectID] ?? .deterministic,
                policyVersion: policyVersion
            )
            return .plan(plan)
        }

        outcomes.append(
            contentsOf: unauthorizedOrder.compactMap { projectID -> AgentPlanOutcome? in
                guard
                    let name = unauthorizedNames[projectID],
                    let files = unauthorizedFiles[projectID]
                else {
                    return nil
                }
                return .needsDestination(
                    projectID: projectID,
                    displayName: name,
                    fileIDs: files
                )
            }
        )

        if outcomes.isEmpty {
            if sawMissingCandidates && !sawUnassigned {
                return [.abstained(.noCandidates)]
            }
            return [.abstained(.classifierAbstained)]
        }
        return outcomes
    }

    /// Records how a proposal actually ended, so the next sweep is better informed.
    public func learn(from outcome: AgentOutcome) async throws {
        try await memory.record(outcome)
    }

    // MARK: - Private

    private func checkCancellation() throws {
        if cancellationRequested {
            throw AgentError.sweepCancelled
        }
    }
}
