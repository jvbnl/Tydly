import Foundation
import GRDB
import XCTest
import TydlyCore
@testable import TydlyPersistence

final class EncryptedOperationLedgerTests: XCTestCase {
    func testDatabaseIsEncryptedAndRejectsWrongKey() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        let schemaVersion = try await ledger.schemaVersion()
        XCTAssertEqual(schemaVersion, 3)
        try await ledger.close()

        let header = Data(try Data(contentsOf: fixture.databaseURL).prefix(16))
        XCTAssertNotEqual(String(data: header, encoding: .utf8), "SQLite format 3\u{0}")

        XCTAssertThrowsError(
            try EncryptedOperationLedger(
                path: fixture.databaseURL.path,
                keyStore: FixedDatabaseKeyStore(byte: 0xBB)
            )
        )
    }

    func testPreparedIntentSurvivesSimulatedCrashAndReopen() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let preparedAt = Date(timeIntervalSince1970: 10)

        var ledger: EncryptedOperationLedger? = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger!)
        let draft = try fixture.moveDraft()
        _ = try await ledger!.prepareBatch(
            id: draft.batchID,
            operations: [draft],
            at: preparedAt
        )
        try await ledger!.close()
        ledger = nil

        let reopened = try fixture.openLedger()
        let operations = try await reopened.nonterminalOperations()
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.phase, .prepared)
        XCTAssertEqual(operations.first?.draft, draft)
        let phases = try await reopened.events(operationID: draft.id).map(\.phase)
        XCTAssertEqual(phases, [.prepared])
        try await reopened.close()
    }

    func testRecoveryFinalizesObservedMoveIdempotently() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let draft = try fixture.moveDraft()
        _ = try await ledger.prepareBatch(id: draft.batchID, operations: [draft])
        let destinationIdentity = try fixture.destinationIdentity()

        let firstRecovery = try await ledger.reconcile(
            operationID: draft.id,
            observation: .matchingDestinationOnly,
            observedDestinationIdentity: destinationIdentity
        )
        XCTAssertEqual(firstRecovery, .markApplied)
        let appliedOperation = try await ledger.operation(id: draft.id)
        XCTAssertEqual(appliedOperation?.phase, .applied)

        let secondRecovery = try await ledger.reconcile(
            operationID: draft.id,
            observation: .matchingDestinationOnly
        )
        XCTAssertEqual(secondRecovery, .markCommitted)
        let committedOperation = try await ledger.operation(id: draft.id)
        XCTAssertEqual(committedOperation?.phase, .committed)

        let finalRecovery = try await ledger.reconcile(
            operationID: draft.id,
            observation: .matchingDestinationOnly
        )
        XCTAssertEqual(finalRecovery, .none)
        let eventPhases = try await ledger.events(operationID: draft.id).map(\.phase)
        XCTAssertEqual(eventPhases, [.prepared, .applied, .committed])
        let batch = try await ledger.batch(id: draft.batchID)
        XCTAssertEqual(batch?.status, .committed)
        try await ledger.close()
    }

    func testAmbiguousRecoveryMovesOperationAndBatchToRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let draft = try fixture.moveDraft()
        _ = try await ledger.prepareBatch(id: draft.batchID, operations: [draft])

        let recovery = try await ledger.reconcile(
            operationID: draft.id,
            observation: .matchingSourceAndDestination
        )
        XCTAssertEqual(recovery, .holdForRepair(.ambiguousPresence))
        let operation = try await ledger.operation(id: draft.id)
        let batch = try await ledger.batch(id: draft.batchID)
        let nonterminal = try await ledger.nonterminalOperations()
        XCTAssertEqual(operation?.phase, .needsRepair)
        XCTAssertEqual(operation?.repairReason, .ambiguousPresence)
        XCTAssertEqual(batch?.status, .needsRepair)
        XCTAssertTrue(nonterminal.isEmpty)
        let repairs = try await ledger.operationsNeedingRepair()
        XCTAssertEqual(repairs.map(\.id), [draft.id])

        let nextIntent = try LedgerOperationIntent(
            id: "move-after-repair",
            batchID: "batch-after-repair",
            ordinal: 0,
            kind: .move,
            sourceRootID: "desktop",
            sourcePath: ScopedRelativePath(rawValue: "other.png"),
            destinationRootID: "atlas",
            destinationPath: ScopedRelativePath(rawValue: "Screens/other.png"),
            expectedSourceIdentity: try LedgerFileIdentity(
                volumeID: "volume",
                fileID: "other",
                byteCount: 1,
                modifiedAt: Date(timeIntervalSince1970: 3),
                fingerprint: "other-fingerprint"
            )
        )
        let nextAuthorization = try LedgerAuthorizationAuthenticator(keyStore: fixture.keyStore)
            .authorizeUserApproval(
                batchID: nextIntent.batchID,
                intents: [nextIntent],
                executionAuthorization: fixture.userApproval()
            )
        let nextDraft = try LedgerOperationDraft(
            intent: nextIntent,
            authorization: nextAuthorization
        )
        do {
            _ = try await ledger.prepareBatch(
                id: nextDraft.batchID,
                operations: [nextDraft]
            )
            XCTFail("unresolved repair must block every new mutation intent")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .repairRequired)
        }
        try await ledger.close()
    }

    func testAuthorizationDigestBindsExactBatchIntent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let valid = try fixture.moveDraft()
        let forged = try LedgerOperationDraft(
            intent: valid.intent,
            authorization: .userApproval(
                planDigest: valid.authorization.intentDigest,
                authenticationTag: Data(repeating: 0, count: 32)
            )
        )

        do {
            _ = try await ledger.prepareBatch(
                id: forged.batchID,
                operations: [forged]
            )
            XCTFail("authorization must be bound to the exact canonical batch")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .authorizationTagInvalid)
        }
        let batch = try await ledger.batch(id: forged.batchID)
        XCTAssertNil(batch)
        try await ledger.close()
    }

    func testAuthenticatorRequiresDeterministicExecutionApproval() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let intent = try fixture.moveDraft().intent
        let authenticator = LedgerAuthorizationAuthenticator(keyStore: fixture.keyStore)

        XCTAssertThrowsError(
            try authenticator.authorizeUserApproval(
                batchID: intent.batchID,
                intents: [intent],
                executionAuthorization: fixture.requiresConsent()
            )
        ) {
            XCTAssertEqual($0 as? LedgerStoreError, .authorizationNotGranted)
        }
    }

    func testCapabilityLossKeepsPreparedOperationResumable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let draft = try fixture.moveDraft()
        _ = try await ledger.prepareBatch(id: draft.batchID, operations: [draft])

        let action = try await ledger.reconcile(
            operationID: draft.id,
            observation: .capabilityUnavailable
        )
        let operation = try await ledger.operation(id: draft.id)
        let batch = try await ledger.batch(id: draft.batchID)
        XCTAssertEqual(action, .holdForRepair(.capabilityUnavailable))
        XCTAssertEqual(operation?.phase, .prepared)
        XCTAssertNil(operation?.repairReason)
        XCTAssertEqual(batch?.status, .active)

        let resumed = try await ledger.reconcile(
            operationID: draft.id,
            observation: .matchingSourceOnly
        )
        XCTAssertEqual(resumed, .retryMutation)
        try await ledger.close()
    }

    func testRootGenerationCannotBeRetargeted() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await ledger.registerRoot(id: "desktop", bookmark: Data("desktop".utf8))

        do {
            try await ledger.registerRoot(id: "desktop", bookmark: Data("other".utf8))
            XCTFail("an existing root ID must remain immutable")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .rootMutationRejected)
        }
        try await ledger.close()
    }

    func testRootRefreshCreatesImmutableMonotonicGeneration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try fixture.openLedger()

        let first = try RootGenerationDescriptor(
            id: "desktop-g0",
            logicalRootID: "desktop",
            generation: 0,
            purpose: .sourceDesktop,
            displayName: "Desktop",
            identity: RootResourceIdentity(volumeID: "volume", fileID: "desktop-file")
        )
        try await ledger.registerRootGeneration(
            first,
            bookmark: Data("bookmark-0".utf8)
        )
        let second = try RootGenerationDescriptor(
            id: "desktop-g1",
            logicalRootID: "desktop",
            generation: 1,
            purpose: .sourceDesktop,
            displayName: "Desktop",
            identity: first.identity
        )
        try await ledger.registerRootGeneration(
            second,
            bookmark: Data("bookmark-1".utf8)
        )

        let binding = try await ledger.rootBinding(logicalRootID: "desktop")
        let active = try await ledger.activeRoot(logicalRootID: "desktop")
        let generations = try await ledger.rootGenerations(logicalRootID: "desktop")
        XCTAssertEqual(binding?.activeRootID, second.id)
        XCTAssertEqual(binding?.status, .active)
        XCTAssertEqual(active?.descriptor, second)
        XCTAssertEqual(generations.map(\.descriptor), [first, second])

        do {
            try await ledger.registerRootGeneration(
                first,
                bookmark: Data("bookmark-0".utf8)
            )
            XCTFail("an old immutable generation must not become active again")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .rootGenerationConflict)
        }

        let skippedGeneration = try RootGenerationDescriptor(
            id: "desktop-g3",
            logicalRootID: "desktop",
            generation: 3,
            purpose: .sourceDesktop,
            displayName: "Desktop",
            identity: first.identity
        )
        do {
            try await ledger.registerRootGeneration(
                skippedGeneration,
                bookmark: Data("bookmark-3".utf8)
            )
            XCTFail("bookmark generations must be contiguous")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .rootGenerationConflict)
        }

        try await ledger.updateRootBindingStatus(
            logicalRootID: "desktop",
            expectedActiveRootID: second.id,
            status: .needsReauthorization
        )
        let held = try await ledger.rootBinding(logicalRootID: "desktop")
        XCTAssertEqual(held?.status, .needsReauthorization)
        try await ledger.close()
    }

    func testPopulatedV1RootMigratesToExplicitReauthorization() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try createLegacyV1Database(
            at: fixture.databaseURL,
            keyStore: fixture.keyStore
        )

        let ledger = try fixture.openLedger()
        let binding = try await ledger.rootBinding(logicalRootID: "legacy-root")
        let root = try await ledger.activeRoot(logicalRootID: "legacy-root")
        let schemaVersion = try await ledger.schemaVersion()
        XCTAssertEqual(schemaVersion, 3)
        XCTAssertEqual(binding?.status, .needsReauthorization)
        XCTAssertEqual(root?.descriptor.purpose, .legacy)
        XCTAssertEqual(root?.descriptor.identity.volumeID, "legacy")
        try await ledger.close()
    }

    func testRootSetRevisionRejectsConcurrentValidationSnapshot() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try fixture.openLedger()
        let snapshot = try await ledger.rootBindingSnapshot()

        let desktop = try RootGenerationDescriptor(
            id: "desktop-g0",
            logicalRootID: "desktop",
            generation: 0,
            purpose: .sourceDesktop,
            displayName: "Desktop",
            identity: RootResourceIdentity(volumeID: "volume", fileID: "desktop")
        )
        try await ledger.registerRootGenerations(
            [
                RootGenerationRegistration(
                    descriptor: desktop,
                    bookmark: Data("desktop".utf8)
                )
            ],
            expectedRootSetRevision: snapshot.revision
        )

        let downloads = try RootGenerationDescriptor(
            id: "downloads-g0",
            logicalRootID: "downloads",
            generation: 0,
            purpose: .sourceDownloads,
            displayName: "Downloads",
            identity: RootResourceIdentity(volumeID: "volume", fileID: "downloads")
        )
        do {
            try await ledger.registerRootGenerations(
                [
                    RootGenerationRegistration(
                        descriptor: downloads,
                        bookmark: Data("downloads".utf8)
                    )
                ],
                expectedRootSetRevision: snapshot.revision
            )
            XCTFail("stale root-set validation must not commit")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .rootBindingConflict)
        }
        try await ledger.close()
    }

    func testExistingV2DatabaseReceivesRootSetRevisionMigration() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try createLegacyV2Database(
            at: fixture.databaseURL,
            keyStore: fixture.keyStore
        )

        let ledger = try fixture.openLedger()
        let snapshot = try await ledger.rootBindingSnapshot()
        let schemaVersion = try await ledger.schemaVersion()
        XCTAssertEqual(schemaVersion, 3)
        XCTAssertEqual(snapshot.revision, 0)
        XCTAssertEqual(snapshot.bindings.first?.status, .needsReauthorization)
        try await ledger.close()
    }

    func testReferencedLegacyOperationsAreHeldForRepairDuringConversion() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = try fixture.openLedger()
        try await ledger.registerRoot(id: "legacy-source", bookmark: Data("source".utf8))
        try await ledger.registerRoot(id: "legacy-destination", bookmark: Data("dest".utf8))

        let intent = try LedgerOperationIntent(
            id: "legacy-move",
            batchID: "legacy-batch",
            ordinal: 0,
            kind: .move,
            sourceRootID: "legacy-source",
            sourcePath: ScopedRelativePath(rawValue: "file"),
            destinationRootID: "legacy-destination",
            destinationPath: ScopedRelativePath(rawValue: "file"),
            expectedSourceIdentity: try fixture.sourceIdentity()
        )
        let authorization = try LedgerAuthorizationAuthenticator(keyStore: fixture.keyStore)
            .authorizeUserApproval(
                batchID: intent.batchID,
                intents: [intent],
                executionAuthorization: fixture.userApproval()
            )
        _ = try await ledger.prepareBatch(
            id: intent.batchID,
            operations: [
                try LedgerOperationDraft(intent: intent, authorization: authorization)
            ]
        )

        let snapshot = try await ledger.rootBindingSnapshot()
        let source = try RootGenerationDescriptor(
            id: "desktop-g0",
            logicalRootID: "source.desktop",
            generation: 0,
            purpose: .sourceDesktop,
            displayName: "Desktop",
            identity: RootResourceIdentity(volumeID: "volume", fileID: "desktop")
        )
        let destination = try RootGenerationDescriptor(
            id: "downloads-g0",
            logicalRootID: "source.downloads",
            generation: 0,
            purpose: .sourceDownloads,
            displayName: "Downloads",
            identity: RootResourceIdentity(volumeID: "volume", fileID: "downloads")
        )
        try await ledger.registerRootGenerations(
            [
                RootGenerationRegistration(
                    descriptor: source,
                    bookmark: Data("desktop".utf8)
                ),
                RootGenerationRegistration(
                    descriptor: destination,
                    bookmark: Data("downloads".utf8)
                )
            ],
            expectedRootSetRevision: snapshot.revision,
            replacingLegacyBindings: true
        )

        let operation = try await ledger.operation(id: intent.id)
        let batch = try await ledger.batch(id: intent.batchID)
        XCTAssertEqual(operation?.phase, .needsRepair)
        XCTAssertEqual(operation?.repairReason, .capabilityUnavailable)
        XCTAssertEqual(batch?.status, .needsRepair)
        let retainedLegacyRoot = try await ledger.root(id: "legacy-source")
        XCTAssertNotNil(retainedLegacyRoot)
        try await ledger.close()
    }

    func testDestinationIdentityCanOnlyBeWrittenOnAppliedTransition() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let draft = try fixture.moveDraft()
        let destinationIdentity = try fixture.destinationIdentity()
        _ = try await ledger.prepareBatch(id: draft.batchID, operations: [draft])
        _ = try await ledger.transition(
            operationID: draft.id,
            to: .applied,
            observedDestinationIdentity: destinationIdentity
        )

        do {
            _ = try await ledger.transition(
                operationID: draft.id,
                to: .committed,
                observedDestinationIdentity: draft.expectedSourceIdentity
            )
            XCTFail("commit must not rewrite destination identity")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .destinationIdentityIsImmutable)
        }
        let operation = try await ledger.operation(id: draft.id)
        XCTAssertEqual(operation?.phase, .applied)
        XCTAssertEqual(operation?.observedDestinationIdentity, destinationIdentity)
        try await ledger.close()
    }

    func testActiveResourcesCannotBeReservedTwice() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let first = try fixture.moveDraft()
        _ = try await ledger.prepareBatch(id: first.batchID, operations: [first])
        let conflictingIntent = try LedgerOperationIntent(
            id: "move-2",
            batchID: "batch-2",
            ordinal: 0,
            kind: .move,
            sourceRootID: first.destinationRootID,
            sourcePath: first.destinationPath,
            destinationRootID: first.sourceRootID,
            destinationPath: try ScopedRelativePath(rawValue: "other.png"),
            expectedSourceIdentity: try fixture.destinationIdentity()
        )
        let conflictingAuthorization = try LedgerAuthorizationAuthenticator(
            keyStore: fixture.keyStore
        ).authorizeUserApproval(
            batchID: conflictingIntent.batchID,
            intents: [conflictingIntent],
            executionAuthorization: fixture.userApproval()
        )
        let conflicting = try LedgerOperationDraft(
            intent: conflictingIntent,
            authorization: conflictingAuthorization
        )

        do {
            _ = try await ledger.prepareBatch(
                id: conflicting.batchID,
                operations: [conflicting]
            )
            XCTFail("active destination must not be reserved as another source")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .activeResourceConflict)
        }
        let conflictingBatch = try await ledger.batch(id: conflicting.batchID)
        XCTAssertNil(conflictingBatch)
        try await ledger.close()
    }

    func testExistingDatabaseNeverGeneratesReplacementKey() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await ledger.close()
        try fixture.keyStore.deleteKey()

        XCTAssertThrowsError(try fixture.openLedger()) { error in
            XCTAssertEqual(error as? LedgerStoreError, .encryptionKeyUnavailable)
        }
        XCTAssertNil(try fixture.keyStore.loadExistingKey())
    }

    func testCommittedInverseMarksOriginalBatchUndone() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let move = try fixture.moveDraft()
        let destinationIdentity = try fixture.destinationIdentity()
        _ = try await ledger.prepareBatch(id: move.batchID, operations: [move])
        _ = try await ledger.transition(
            operationID: move.id,
            to: .applied,
            observedDestinationIdentity: destinationIdentity
        )
        _ = try await ledger.transition(operationID: move.id, to: .committed)

        let undoIntent = try LedgerOperationIntent(
            id: "undo-1",
            batchID: "undo-batch",
            ordinal: 0,
            kind: .undo,
            sourceRootID: move.destinationRootID,
            sourcePath: move.destinationPath,
            destinationRootID: move.sourceRootID,
            destinationPath: move.sourcePath,
            expectedSourceIdentity: destinationIdentity,
            reversesOperationID: move.id
        )
        let undoAuthorization = try LedgerAuthorizationAuthenticator(keyStore: fixture.keyStore)
            .authorizeUserApproval(
                batchID: undoIntent.batchID,
                intents: [undoIntent],
                executionAuthorization: fixture.userApproval()
            )
        let undo = try LedgerOperationDraft(
            intent: undoIntent,
            authorization: undoAuthorization
        )
        _ = try await ledger.prepareBatch(id: undo.batchID, operations: [undo])
        _ = try await ledger.transition(
            operationID: undo.id,
            to: .applied,
            observedDestinationIdentity: move.expectedSourceIdentity
        )
        _ = try await ledger.transition(operationID: undo.id, to: .committed)

        let moveBatch = try await ledger.batch(id: move.batchID)
        let undoBatch = try await ledger.batch(id: undo.batchID)
        XCTAssertEqual(moveBatch?.status, .undone)
        XCTAssertEqual(undoBatch?.status, .committed)
        try await ledger.close()
    }

    func testInvalidInverseIsRejectedBeforeBatchPersists() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let move = try fixture.moveDraft()
        let invalidUndoIntent = try LedgerOperationIntent(
            id: "undo-invalid",
            batchID: "undo-batch",
            ordinal: 0,
            kind: .undo,
            sourceRootID: move.destinationRootID,
            sourcePath: move.destinationPath,
            destinationRootID: move.sourceRootID,
            destinationPath: move.sourcePath,
            expectedSourceIdentity: move.expectedSourceIdentity,
            reversesOperationID: move.id
        )
        let invalidUndoAuthorization = try LedgerAuthorizationAuthenticator(
            keyStore: fixture.keyStore
        ).authorizeUserApproval(
            batchID: invalidUndoIntent.batchID,
            intents: [invalidUndoIntent],
            executionAuthorization: fixture.userApproval()
        )
        let invalidUndo = try LedgerOperationDraft(
            intent: invalidUndoIntent,
            authorization: invalidUndoAuthorization
        )

        do {
            _ = try await ledger.prepareBatch(
                id: invalidUndo.batchID,
                operations: [invalidUndo]
            )
            XCTFail("uncommitted operation must not be reversible")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .invalidInverseOperation)
        }
        let invalidBatch = try await ledger.batch(id: invalidUndo.batchID)
        XCTAssertNil(invalidBatch)
        try await ledger.close()
    }

    func testBackupIsEncryptedVerifiedAndReadable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupURL = fixture.directory.appendingPathComponent("backup.sqlite")

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let move = try fixture.moveDraft()
        _ = try await ledger.prepareBatch(id: move.batchID, operations: [move])
        try await ledger.backup(to: backupURL)

        let header = Data(try Data(contentsOf: backupURL).prefix(16))
        XCTAssertNotEqual(String(data: header, encoding: .utf8), "SQLite format 3\u{0}")

        let backup = try EncryptedOperationLedger(
            path: backupURL.path,
            keyStore: fixture.keyStore
        )
        let backedUpOperation = try await backup.operation(id: move.id)
        XCTAssertEqual(backedUpOperation?.draft, move)
        try await backup.integrityCheck()
        try await backup.close()
        try await ledger.close()
    }
}

private func createLegacyV1Database(
    at url: URL,
    keyStore: any DatabaseKeyStore
) throws {
    guard let key = try keyStore.loadExistingKey() else {
        throw LedgerStoreError.encryptionKeyUnavailable
    }
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
        try db.usePassphrase(key)
        _ = try db.cipherVersion
    }
    let database = try DatabaseQueue(path: url.path, configuration: configuration)
    try database.write { db in
        try db.execute(sql: """
            CREATE TABLE roots (
                id TEXT PRIMARY KEY NOT NULL,
                bookmark BLOB NOT NULL,
                bookmarkVersion INTEGER NOT NULL,
                createdAt DOUBLE NOT NULL,
                updatedAt DOUBLE NOT NULL
            );
            CREATE TABLE batches (
                id TEXT PRIMARY KEY NOT NULL,
                status TEXT NOT NULL,
                createdAt DOUBLE NOT NULL,
                updatedAt DOUBLE NOT NULL
            );
            CREATE TABLE operations (
                id TEXT PRIMARY KEY NOT NULL,
                batchID TEXT NOT NULL REFERENCES batches(id),
                ordinal INTEGER NOT NULL,
                kind TEXT NOT NULL,
                sourceRootID TEXT NOT NULL REFERENCES roots(id),
                sourceRelativePath TEXT NOT NULL,
                destinationRootID TEXT NOT NULL REFERENCES roots(id),
                destinationRelativePath TEXT NOT NULL,
                expectedSourceIdentity BLOB NOT NULL,
                observedDestinationIdentity BLOB,
                reversesOperationID TEXT REFERENCES operations(id),
                authorization BLOB NOT NULL,
                phase TEXT NOT NULL,
                repairReason TEXT,
                createdAt DOUBLE NOT NULL,
                updatedAt DOUBLE NOT NULL
            );
            CREATE TABLE operationEvents (
                sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                operationID TEXT NOT NULL REFERENCES operations(id),
                phase TEXT NOT NULL,
                timestamp DOUBLE NOT NULL,
                errorDomain TEXT,
                errorCode INTEGER
            );
            CREATE TABLE grdb_migrations (
                identifier TEXT NOT NULL PRIMARY KEY
            );
            INSERT INTO grdb_migrations (identifier)
                VALUES ('operation-ledger-v1');
            INSERT INTO roots (
                id, bookmark, bookmarkVersion, createdAt, updatedAt
            ) VALUES ('legacy-root', X'010203', 1, 1, 1);
            """)
    }
    try database.close()
}

private func createLegacyV2Database(
    at url: URL,
    keyStore: any DatabaseKeyStore
) throws {
    try createLegacyV1Database(at: url, keyStore: keyStore)
    guard let key = try keyStore.loadExistingKey() else {
        throw LedgerStoreError.encryptionKeyUnavailable
    }
    var configuration = Configuration()
    configuration.foreignKeysEnabled = true
    configuration.prepareDatabase { db in
        try db.usePassphrase(key)
        _ = try db.cipherVersion
    }
    let database = try DatabaseQueue(path: url.path, configuration: configuration)
    try database.write { db in
        try db.execute(sql: """
            ALTER TABLE roots
                ADD COLUMN logicalRootID TEXT NOT NULL DEFAULT '';
            ALTER TABLE roots
                ADD COLUMN generation INTEGER NOT NULL DEFAULT 0;
            ALTER TABLE roots
                ADD COLUMN purpose TEXT NOT NULL DEFAULT 'legacy';
            ALTER TABLE roots
                ADD COLUMN displayName TEXT NOT NULL DEFAULT '';
            ALTER TABLE roots
                ADD COLUMN volumeID TEXT NOT NULL DEFAULT 'legacy';
            ALTER TABLE roots
                ADD COLUMN resourceID TEXT NOT NULL DEFAULT '';
            UPDATE roots
            SET logicalRootID = id, displayName = id, resourceID = id;
            CREATE UNIQUE INDEX rootGenerationByLogicalID
                ON roots(logicalRootID, generation);
            CREATE TABLE rootBindings (
                logicalRootID TEXT PRIMARY KEY NOT NULL,
                activeRootID TEXT NOT NULL UNIQUE REFERENCES roots(id),
                purpose TEXT NOT NULL,
                status TEXT NOT NULL,
                updatedAt DOUBLE NOT NULL
            );
            INSERT INTO rootBindings (
                logicalRootID, activeRootID, purpose, status, updatedAt
            )
            SELECT logicalRootID, id, purpose, 'needsReauthorization', updatedAt
            FROM roots;
            INSERT INTO grdb_migrations (identifier)
                VALUES ('root-capability-generations-v2');
            """)
    }
    try database.close()
}

private struct Fixture {
    let directory: URL
    let databaseURL: URL
    let keyStore = FixedDatabaseKeyStore(byte: 0xAA)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TydlyLedgerTests-\(UUID().uuidString)", isDirectory: true)
        databaseURL = directory.appendingPathComponent("ledger.sqlite")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
    }

    func openLedger() throws -> EncryptedOperationLedger {
        try EncryptedOperationLedger(path: databaseURL.path, keyStore: keyStore)
    }

    func registerRoots(in ledger: EncryptedOperationLedger) async throws {
        try await ledger.registerRoot(id: "desktop", bookmark: Data("desktop".utf8))
        try await ledger.registerRoot(id: "atlas", bookmark: Data("atlas".utf8))
    }

    func userApproval() -> ExecutionAuthorization {
        Rules.authorizeUserApprovedExecution(subscription: .active)
    }

    func requiresConsent() -> ExecutionAuthorization {
        Rules.authorizeAutomaticExecution(
            rule: nil,
            sensitivity: .clearedForCurrentFingerprint,
            coverage: .complete,
            subscription: .active
        )
    }

    func moveDraft() throws -> LedgerOperationDraft {
        let intent = try LedgerOperationIntent(
            id: "move-1",
            batchID: "move-batch",
            ordinal: 0,
            kind: .move,
            sourceRootID: "desktop",
            sourcePath: ScopedRelativePath(rawValue: "shot.png"),
            destinationRootID: "atlas",
            destinationPath: ScopedRelativePath(rawValue: "Screens/shot.png"),
            expectedSourceIdentity: sourceIdentity()
        )
        let authorization = try LedgerAuthorizationAuthenticator(keyStore: keyStore)
            .authorizeUserApproval(
                batchID: intent.batchID,
                intents: [intent],
                executionAuthorization: userApproval()
            )
        return try LedgerOperationDraft(
            intent: intent,
            authorization: authorization
        )
    }

    func sourceIdentity() throws -> LedgerFileIdentity {
        try LedgerFileIdentity(
            volumeID: "volume",
            fileID: "source-file",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSince1970: 1),
            fingerprint: "source-fingerprint"
        )
    }

    func destinationIdentity() throws -> LedgerFileIdentity {
        try LedgerFileIdentity(
            volumeID: "volume",
            fileID: "destination-file",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSince1970: 2),
            fingerprint: "destination-fingerprint"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class FixedDatabaseKeyStore: DatabaseKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?

    init(byte: UInt8) {
        key = Data(repeating: byte, count: KeychainDatabaseKeyStore.keyLength)
    }

    func loadOrCreateKey() throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard let key else {
            throw LedgerStoreError.encryptionKeyUnavailable
        }
        return key
    }

    func loadExistingKey() throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return key
    }

    func deleteKey() throws {
        lock.lock()
        defer { lock.unlock() }
        if var existing = key {
            existing.resetBytes(in: 0..<existing.count)
        }
        key = nil
    }
}
