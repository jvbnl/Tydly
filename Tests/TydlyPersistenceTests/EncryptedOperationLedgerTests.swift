import Foundation
import XCTest
import TydlyCore
@testable import TydlyPersistence

final class EncryptedOperationLedgerTests: XCTestCase {
    func testDatabaseIsEncryptedAndRejectsWrongKey() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        XCTAssertEqual(try await ledger.schemaVersion(), 1)
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
        XCTAssertEqual(
            try await reopened.events(operationID: draft.id).map(\.phase),
            [.prepared]
        )
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

        XCTAssertEqual(
            try await ledger.reconcile(
                operationID: draft.id,
                observation: .matchingDestinationOnly,
                observedDestinationIdentity: destinationIdentity
            ),
            .markApplied
        )
        XCTAssertEqual(try await ledger.operation(id: draft.id)?.phase, .applied)

        XCTAssertEqual(
            try await ledger.reconcile(
                operationID: draft.id,
                observation: .matchingDestinationOnly
            ),
            .markCommitted
        )
        XCTAssertEqual(try await ledger.operation(id: draft.id)?.phase, .committed)

        XCTAssertEqual(
            try await ledger.reconcile(
                operationID: draft.id,
                observation: .matchingDestinationOnly
            ),
            .none
        )
        XCTAssertEqual(
            try await ledger.events(operationID: draft.id).map(\.phase),
            [.prepared, .applied, .committed]
        )
        XCTAssertEqual(try await ledger.batch(id: draft.batchID)?.status, .committed)
        try await ledger.close()
    }

    func testAmbiguousRecoveryMovesOperationAndBatchToRepair() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let draft = try fixture.moveDraft()
        _ = try await ledger.prepareBatch(id: draft.batchID, operations: [draft])

        XCTAssertEqual(
            try await ledger.reconcile(
                operationID: draft.id,
                observation: .matchingSourceAndDestination
            ),
            .holdForRepair(.ambiguousPresence)
        )
        XCTAssertEqual(try await ledger.operation(id: draft.id)?.phase, .needsRepair)
        XCTAssertEqual(try await ledger.batch(id: draft.batchID)?.status, .needsRepair)
        XCTAssertTrue(try await ledger.nonterminalOperations().isEmpty)
        try await ledger.close()
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

        let undo = try LedgerOperationDraft(
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
        _ = try await ledger.prepareBatch(id: undo.batchID, operations: [undo])
        _ = try await ledger.transition(
            operationID: undo.id,
            to: .applied,
            observedDestinationIdentity: move.expectedSourceIdentity
        )
        _ = try await ledger.transition(operationID: undo.id, to: .committed)

        XCTAssertEqual(try await ledger.batch(id: move.batchID)?.status, .undone)
        XCTAssertEqual(try await ledger.batch(id: undo.batchID)?.status, .committed)
        try await ledger.close()
    }

    func testInvalidInverseIsRejectedBeforeBatchPersists() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let ledger = try fixture.openLedger()
        try await fixture.registerRoots(in: ledger)
        let move = try fixture.moveDraft()
        let invalidUndo = try LedgerOperationDraft(
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

        do {
            _ = try await ledger.prepareBatch(
                id: invalidUndo.batchID,
                operations: [invalidUndo]
            )
            XCTFail("uncommitted operation must not be reversible")
        } catch {
            XCTAssertEqual(error as? LedgerStoreError, .invalidInverseOperation)
        }
        XCTAssertNil(try await ledger.batch(id: invalidUndo.batchID))
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
        XCTAssertEqual(try await backup.operation(id: move.id)?.draft, move)
        try await backup.integrityCheck()
        try await backup.close()
        try await ledger.close()
    }
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

    func moveDraft() throws -> LedgerOperationDraft {
        try LedgerOperationDraft(
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
