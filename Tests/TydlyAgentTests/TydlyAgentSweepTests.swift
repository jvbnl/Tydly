import XCTest
import TydlyAgent
import TydlyCore

final class TydlyAgentSweepTests: XCTestCase {
    private func makeAgent(
        memory: StubMemory = StubMemory(projects: [], candidatesByFileID: [:]),
        classifier: StubClassifier = StubClassifier(),
        conditions: SystemConditions = .idle
    ) -> TydlyAgent {
        TydlyAgent(
            memory: memory,
            classifier: classifier,
            conditions: StubConditions(conditions),
            policyVersion: 7
        )
    }

    // MARK: - Admission

    func testOnlyOneSweepAtATime() async {
        let agent = makeAgent()

        let first = await agent.beginSweep(posture: .orchestrating)
        guard case .success = first else {
            return XCTFail("first sweep should be admitted")
        }

        let second = await agent.beginSweep(posture: .orchestrating)
        guard case let .failure(refusal) = second else {
            return XCTFail("second concurrent sweep must be refused")
        }
        XCTAssertEqual(refusal, .alreadySweeping)
    }

    func testSweepCanRestartAfterEnding() async {
        let agent = makeAgent()

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("first sweep should be admitted")
        }
        await agent.endSweep(token)

        let isSweeping = await agent.isSweeping
        XCTAssertFalse(isSweeping)

        guard case .success = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("a sweep should be admitted once the previous one ended")
        }
    }

    func testWatchOnlyPostureRefusesTheSweep() async {
        let agent = makeAgent()

        let result = await agent.beginSweep(
            posture: .watchOnly(.modelUnavailable(.appleIntelligenceDisabled))
        )
        guard case let .failure(refusal) = result else {
            return XCTFail("watch-only must refuse a sweep")
        }
        XCTAssertEqual(refusal, .watchOnly(.modelUnavailable(.appleIntelligenceDisabled)))

        let isSweeping = await agent.isSweeping
        XCTAssertFalse(isSweeping, "a refused sweep must not occupy the slot")
    }

    func testSystemPressureDefersTheSweep() async {
        let agent = makeAgent(conditions: SystemConditions(isThermallyPressured: true))

        let result = await agent.beginSweep(posture: .orchestrating)
        guard case let .failure(refusal) = result else {
            return XCTFail("thermal pressure must defer the sweep")
        }
        XCTAssertEqual(refusal, .deferred(.thermal))
    }

    func testStaleTokenCannotEndANewerSweep() async {
        let agent = makeAgent()

        guard case let .success(first) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("first sweep should be admitted")
        }
        await agent.endSweep(first)
        guard case .success = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("second sweep should be admitted")
        }

        await agent.endSweep(first)

        let isSweeping = await agent.isSweeping
        XCTAssertTrue(isSweeping, "a stale token must not end the current sweep")
    }

    func testReasoningRejectsAStaleToken() async throws {
        let agent = makeAgent()

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        await agent.endSweep(token)

        do {
            _ = try await agent.reason(
                about: [Fixture.bundle(fileID: "f1")],
                posture: .orchestrating,
                token: token
            )
            XCTFail("reasoning under a finished sweep must throw")
        } catch let error as AgentError {
            XCTAssertEqual(error, .sweepNotActive)
        }
    }

    func testCancellationStopsReasoning() async throws {
        let memory = StubMemory(
            projects: [Fixture.atlas()],
            candidatesByFileID: ["f1": [Fixture.atlasCandidate]]
        )
        let agent = makeAgent(memory: memory)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        await agent.cancelActiveSweep()

        do {
            _ = try await agent.reason(
                about: [Fixture.bundle(fileID: "f1")],
                posture: .orchestrating,
                token: token
            )
            XCTFail("a cancelled sweep must not produce proposals")
        } catch let error as AgentError {
            XCTAssertEqual(error, .sweepCancelled)
        }
    }

    // MARK: - Reasoning

    func testGroupsFilesByProjectIntoOnePlan() async throws {
        let memory = StubMemory(
            projects: [Fixture.atlas()],
            candidatesByFileID: [
                "f1": [Fixture.atlasCandidate],
                "f2": [Fixture.atlasCandidate]
            ]
        )
        let classifier = StubClassifier(resultsByFileID: [
            "f1": Fixture.selecting("atlas", evidenceIDs: ["e-f1"]),
            "f2": Fixture.selecting("atlas", evidenceIDs: ["e-f2"])
        ])
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [Fixture.bundle(fileID: "f1"), Fixture.bundle(fileID: "f2")],
            posture: .orchestrating,
            token: token
        )

        XCTAssertEqual(outcomes.count, 1)
        guard case let .plan(plan) = outcomes[0] else {
            return XCTFail("expected one grouped plan")
        }
        XCTAssertEqual(plan.projectID, "atlas")
        XCTAssertEqual(plan.fileCount, 2)
        XCTAssertEqual(plan.policyVersion, 7)
        XCTAssertEqual(plan.supportingEvidenceIDs, ["e-f1", "e-f2"])
        XCTAssertEqual(
            plan.moves.map(\.destinationRootGenerationID),
            ["dest-atlas-g1", "dest-atlas-g1"]
        )
    }

    // The model can never invent a destination path — an unauthorized project becomes an ask.
    func testProjectWithoutAuthorizedDestinationAsksForOne() async throws {
        let memory = StubMemory(
            projects: [Fixture.atlas(destination: nil)],
            candidatesByFileID: [
                "f1": [Fixture.atlasCandidate],
                "f2": [Fixture.atlasCandidate]
            ]
        )
        let classifier = StubClassifier(resultsByFileID: [
            "f1": Fixture.selecting("atlas"),
            "f2": Fixture.selecting("atlas")
        ])
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [Fixture.bundle(fileID: "f1"), Fixture.bundle(fileID: "f2")],
            posture: .orchestrating,
            token: token
        )

        XCTAssertEqual(
            outcomes,
            [.needsDestination(projectID: "atlas", displayName: "Atlas", fileIDs: ["f1", "f2"])],
            "the whole group should be asked about once, not per file"
        )
    }

    // Defense in depth: an identifier outside the allowlist is an abstention, not a move.
    func testProjectOutsideTheCandidateAllowlistIsRejected() async throws {
        let memory = StubMemory(
            projects: [
                Fixture.atlas(),
                ProjectMemory(
                    id: "payroll",
                    displayName: "Payroll",
                    destinationGenerationID: "dest-payroll-g1"
                )
            ],
            candidatesByFileID: ["f1": [Fixture.atlasCandidate]]
        )
        let classifier = StubClassifier(resultsByFileID: [
            "f1": Fixture.selecting("payroll")
        ])
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [Fixture.bundle(fileID: "f1")],
            posture: .orchestrating,
            token: token
        )

        XCTAssertEqual(outcomes, [.abstained(.classifierAbstained)])
    }

    // The lattice is monotonic: the model raises sensitivity and can never clear it.
    func testModelCanRaiseSensitivityButNotClearIt() async throws {
        let memory = StubMemory(
            projects: [Fixture.atlas()],
            candidatesByFileID: [
                "raise": [Fixture.atlasCandidate],
                "clear": [Fixture.atlasCandidate]
            ]
        )
        let classifier = StubClassifier(resultsByFileID: [
            "raise": Fixture.selecting("atlas", sensitivity: .sensitive),
            "clear": Fixture.selecting("atlas", sensitivity: .clearedForCurrentFingerprint)
        ])
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [
                Fixture.bundle(fileID: "raise", sensitivity: .clearedForCurrentFingerprint),
                Fixture.bundle(fileID: "clear", sensitivity: .sensitive)
            ],
            posture: .orchestrating,
            token: token
        )

        guard case let .plan(plan) = outcomes[0] else {
            return XCTFail("expected a plan")
        }
        let byFileID = Dictionary(uniqueKeysWithValues: plan.moves.map { ($0.fileID, $0) })
        XCTAssertEqual(byFileID["raise"]?.sensitivity, .sensitive, "model may raise")
        XCTAssertEqual(byFileID["clear"]?.sensitivity, .sensitive, "model may never clear")
    }

    // Rule 2 makes sensitive files ask-first, not invisible — they are still proposed.
    func testSensitiveFilesAreStillProposed() async throws {
        let memory = StubMemory(
            projects: [Fixture.atlas()],
            candidatesByFileID: ["f1": [Fixture.atlasCandidate]]
        )
        let classifier = StubClassifier(resultsByFileID: [
            "f1": Fixture.selecting("atlas", sensitivity: .sensitive)
        ])
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [Fixture.bundle(fileID: "f1", sensitivity: .sensitive)],
            posture: .orchestrating,
            token: token
        )

        guard case let .plan(plan) = outcomes[0] else {
            return XCTFail("a sensitive file must still be proposed")
        }
        XCTAssertTrue(plan.isPermanentlyAskFirst)

        // …and policy still refuses to let it file itself automatically.
        XCTAssertEqual(
            Rules.automaticFilingDenial(
                rule: FilingRule(id: "r", name: "R", kind: .screenshot, autonomy: .auto),
                sensitivity: plan.moves[0].sensitivity,
                coverage: plan.moves[0].coverage,
                subscription: .active
            ),
            .sensitiveContent
        )
    }

    func testNoCandidatesAbstainsWithoutInvokingTheModel() async throws {
        let memory = StubMemory(projects: [Fixture.atlas()], candidatesByFileID: [:])
        let classifier = StubClassifier()
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [Fixture.bundle(fileID: "f1")],
            posture: .orchestrating,
            token: token
        )

        XCTAssertEqual(outcomes, [.abstained(.noCandidates)])
        let requests = await classifier.observedRequestCount()
        XCTAssertEqual(requests, 0, "the model must not be invoked without candidates")
    }

    func testEmptyEvidenceAbstains() async throws {
        let agent = makeAgent()

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [],
            posture: .orchestrating,
            token: token
        )

        XCTAssertEqual(outcomes, [.abstained(.noEvidence)])
    }

    func testWatchOnlyPostureProducesNoProposalEvenWithEvidence() async throws {
        let memory = StubMemory(
            projects: [Fixture.atlas()],
            candidatesByFileID: ["f1": [Fixture.atlasCandidate]]
        )
        let classifier = StubClassifier(resultsByFileID: ["f1": Fixture.selecting("atlas")])
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        let outcomes = try await agent.reason(
            about: [Fixture.bundle(fileID: "f1")],
            posture: .watchOnly(.resting),
            token: token
        )

        XCTAssertEqual(outcomes, [.abstained(.watchOnly(.resting))])
        let requests = await classifier.observedRequestCount()
        XCTAssertEqual(requests, 0, "watch-only must not reach the model")
    }

    // AI_ENGINE.md §Efficiency policy — one model request at a time.
    func testModelRequestsAreSerialized() async throws {
        let files = (1...6).map { "f\($0)" }
        let memory = StubMemory(
            projects: [Fixture.atlas()],
            candidatesByFileID: Dictionary(
                uniqueKeysWithValues: files.map { ($0, [Fixture.atlasCandidate]) }
            )
        )
        let classifier = StubClassifier(
            resultsByFileID: Dictionary(
                uniqueKeysWithValues: files.map { ($0, Fixture.selecting("atlas")) }
            )
        )
        let agent = makeAgent(memory: memory, classifier: classifier)

        guard case let .success(token) = await agent.beginSweep(posture: .orchestrating) else {
            return XCTFail("sweep should be admitted")
        }
        _ = try await agent.reason(
            about: files.map { Fixture.bundle(fileID: $0) },
            posture: .orchestrating,
            token: token
        )

        let peak = await classifier.observedMaxConcurrent()
        XCTAssertEqual(peak, 1)
    }

    func testLearningIsRecorded() async throws {
        let memory = StubMemory(projects: [], candidatesByFileID: [:])
        let agent = makeAgent(memory: memory)

        let outcome = AgentOutcome(
            fileID: "f1",
            fingerprint: "fp-f1",
            predictedProjectID: "atlas",
            actualProjectID: "finance",
            kind: .correctedToOtherProject,
            source: .foundationModel,
            extractorRevision: 3,
            policyVersion: 7
        )
        try await agent.learn(from: outcome)

        let recorded = await memory.recordedOutcomes()
        XCTAssertEqual(recorded, [outcome])
    }
}
