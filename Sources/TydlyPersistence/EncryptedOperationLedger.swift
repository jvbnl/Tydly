import Foundation
import GRDB
import TydlyCore

public enum LedgerStoreError: Error, Equatable, Sendable {
    case encryptionKeyUnavailable
    case emptyBatch
    case mismatchedBatch
    case duplicateOperationOrOrdinal
    case operationNotFound
    case invalidTransition(LedgerOperationPhase, LedgerOperationPhase)
    case concurrentTransition
    case missingDestinationIdentity
    case invalidInverseOperation
    case invalidErrorDomain
    case integrityCheckFailed
    case backupDestinationExists
    case backupVerificationFailed
}

public struct LedgerRootRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let bookmark: Data
    public let bookmarkVersion: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String,
        bookmark: Data,
        bookmarkVersion: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.bookmark = bookmark
        self.bookmarkVersion = bookmarkVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Single-writer encrypted source of truth for move intent and recovery. This target owns no
/// filesystem mutation API: an engine must commit `prepared`, perform one validated action,
/// then compare-and-swap the operation to `applied` and `committed`.
public actor EncryptedOperationLedger {
    private let database: DatabaseQueue
    private let keyStore: any DatabaseKeyStore
    public let path: String

    public init(path: String, keyStore: any DatabaseKeyStore) throws {
        self.path = path
        self.keyStore = keyStore

        let databaseURL = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        var key = try keyStore.loadOrCreateKey()
        defer { key.resetBytes(in: 0..<key.count) }
        database = try Self.openDatabase(path: path, key: key)
        try Self.migrator.migrate(database)
        try Self.verifyIntegrity(database)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
    }

    public func close() throws {
        try database.close()
    }

    public func registerRoot(
        id: String,
        bookmark: Data,
        bookmarkVersion: Int = 1,
        at date: Date = Date()
    ) throws {
        guard !id.isEmpty, !bookmark.isEmpty else {
            throw LedgerValidationError.emptyIdentifier
        }
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO roots (
                        id, bookmark, bookmarkVersion, createdAt, updatedAt
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        bookmark = excluded.bookmark,
                        bookmarkVersion = excluded.bookmarkVersion,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    id,
                    bookmark,
                    bookmarkVersion,
                    date.timeIntervalSince1970,
                    date.timeIntervalSince1970
                ]
            )
        }
    }

    public func root(id: String) throws -> LedgerRootRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM roots WHERE id = ?",
                arguments: [id]
            ) else {
                return nil
            }
            return Self.decodeRoot(row)
        }
    }

    /// Atomically writes the batch, every immutable operation intent, and each `prepared`
    /// event. Returning successfully is the precondition for touching the filesystem.
    @discardableResult
    public func prepareBatch(
        id: String,
        operations: [LedgerOperationDraft],
        at date: Date = Date()
    ) throws -> LedgerBatch {
        guard !id.isEmpty, !operations.isEmpty else {
            throw LedgerStoreError.emptyBatch
        }
        guard operations.allSatisfy({ $0.batchID == id }) else {
            throw LedgerStoreError.mismatchedBatch
        }
        guard Set(operations.map(\.id)).count == operations.count,
              Set(operations.map(\.ordinal)).count == operations.count else {
            throw LedgerStoreError.duplicateOperationOrOrdinal
        }

        return try database.write { db in
            for operation in operations where operation.kind == .undo {
                try Self.validateInverse(operation, in: db)
            }

            let timestamp = date.timeIntervalSince1970
            try db.execute(
                sql: """
                    INSERT INTO batches (id, status, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [id, LedgerBatchStatus.active.rawValue, timestamp, timestamp]
            )

            for operation in operations.sorted(by: { $0.ordinal < $1.ordinal }) {
                let expectedIdentity = try Self.encodeIdentity(operation.expectedSourceIdentity)
                try db.execute(
                    sql: """
                        INSERT INTO operations (
                            id, batchID, ordinal, kind,
                            sourceRootID, sourceRelativePath,
                            destinationRootID, destinationRelativePath,
                            expectedSourceIdentity, observedDestinationIdentity,
                            reversesOperationID, phase, createdAt, updatedAt
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?)
                        """,
                    arguments: [
                        operation.id,
                        operation.batchID,
                        operation.ordinal,
                        operation.kind.rawValue,
                        operation.sourceRootID,
                        operation.sourcePath.rawValue,
                        operation.destinationRootID,
                        operation.destinationPath.rawValue,
                        expectedIdentity,
                        operation.reversesOperationID,
                        LedgerOperationPhase.prepared.rawValue,
                        timestamp,
                        timestamp
                    ]
                )
                try Self.insertEvent(
                    db,
                    operationID: operation.id,
                    phase: .prepared,
                    date: date,
                    errorDomain: nil,
                    errorCode: nil
                )
            }

            return LedgerBatch(
                id: id,
                status: .active,
                createdAt: date,
                updatedAt: date
            )
        }
    }

    @discardableResult
    public func transition(
        operationID: String,
        to nextPhase: LedgerOperationPhase,
        observedDestinationIdentity: LedgerFileIdentity? = nil,
        errorDomain: String? = nil,
        errorCode: Int? = nil,
        at date: Date = Date()
    ) throws -> LedgerOperation {
        if let errorDomain,
           errorDomain.count > 128 || errorDomain.contains("/") || errorDomain.contains("\\") {
            throw LedgerStoreError.invalidErrorDomain
        }

        return try database.write { db in
            guard let current = try Self.fetchOperation(id: operationID, from: db) else {
                throw LedgerStoreError.operationNotFound
            }
            guard LedgerTransition.allows(from: current.phase, to: nextPhase) else {
                throw LedgerStoreError.invalidTransition(current.phase, nextPhase)
            }

            let resultingIdentity: LedgerFileIdentity?
            if nextPhase == .applied {
                guard let observedDestinationIdentity else {
                    throw LedgerStoreError.missingDestinationIdentity
                }
                resultingIdentity = observedDestinationIdentity
            } else {
                resultingIdentity = observedDestinationIdentity ?? current.observedDestinationIdentity
            }

            let encodedIdentity = try resultingIdentity.map(Self.encodeIdentity)
            try db.execute(
                sql: """
                    UPDATE operations
                    SET phase = ?, observedDestinationIdentity = ?, updatedAt = ?
                    WHERE id = ? AND phase = ?
                    """,
                arguments: [
                    nextPhase.rawValue,
                    encodedIdentity,
                    date.timeIntervalSince1970,
                    operationID,
                    current.phase.rawValue
                ]
            )
            guard db.changesCount == 1 else {
                throw LedgerStoreError.concurrentTransition
            }

            try Self.insertEvent(
                db,
                operationID: operationID,
                phase: nextPhase,
                date: date,
                errorDomain: errorDomain,
                errorCode: errorCode
            )
            try Self.refreshBatchStatus(current.draft.batchID, in: db, at: date)
            if nextPhase == .committed, current.draft.kind == .undo {
                try Self.refreshOriginalBatchStatus(for: current.draft, in: db, at: date)
            }

            guard let updated = try Self.fetchOperation(id: operationID, from: db) else {
                throw LedgerStoreError.operationNotFound
            }
            return updated
        }
    }

    /// Records safe, metadata-only state changes from the pure recovery matrix. A retry is
    /// returned to the engine and is never performed by the ledger.
    @discardableResult
    public func reconcile(
        operationID: String,
        observation: FileSystemObservation,
        observedDestinationIdentity: LedgerFileIdentity? = nil,
        at date: Date = Date()
    ) throws -> LedgerRecoveryAction {
        guard let current = try operation(id: operationID) else {
            throw LedgerStoreError.operationNotFound
        }
        let action = LedgerRecovery.action(phase: current.phase, observation: observation)

        switch action {
        case .markApplied:
            _ = try transition(
                operationID: operationID,
                to: .applied,
                observedDestinationIdentity: observedDestinationIdentity,
                at: date
            )
        case .markCommitted:
            _ = try transition(operationID: operationID, to: .committed, at: date)
        case .markAborted:
            _ = try transition(operationID: operationID, to: .aborted, at: date)
        case .holdForRepair:
            if current.phase != .needsRepair {
                _ = try transition(operationID: operationID, to: .needsRepair, at: date)
            }
        case .retryMutation, .none:
            break
        }
        return action
    }

    public func operation(id: String) throws -> LedgerOperation? {
        try database.read { db in
            try Self.fetchOperation(id: id, from: db)
        }
    }

    public func operations(batchID: String) throws -> [LedgerOperation] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM operations WHERE batchID = ? ORDER BY ordinal",
                arguments: [batchID]
            )
            return try rows.map(Self.decodeOperation)
        }
    }

    public func batch(id: String) throws -> LedgerBatch? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM batches WHERE id = ?",
                arguments: [id]
            ) else {
                return nil
            }
            guard let status = LedgerBatchStatus(rawValue: row["status"]) else {
                throw LedgerStoreError.integrityCheckFailed
            }
            return LedgerBatch(
                id: row["id"],
                status: status,
                createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
            )
        }
    }

    public func nonterminalOperations() throws -> [LedgerOperation] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM operations
                    WHERE phase IN (?, ?)
                    ORDER BY createdAt, batchID, ordinal
                    """,
                arguments: [
                    LedgerOperationPhase.prepared.rawValue,
                    LedgerOperationPhase.applied.rawValue
                ]
            )
            return try rows.map(Self.decodeOperation)
        }
    }

    public func events(operationID: String) throws -> [LedgerEvent] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM operationEvents
                    WHERE operationID = ?
                    ORDER BY sequence
                    """,
                arguments: [operationID]
            )
            return try rows.map(Self.decodeEvent)
        }
    }

    public func integrityCheck() throws {
        try Self.verifyIntegrity(database)
    }

    public func schemaVersion() throws -> Int {
        try database.read { db in
            try Int.fetchOne(db, sql: "PRAGMA user_version") ?? 0
        }
    }

    /// Creates a compact, consistently encrypted snapshot and verifies it with the same
    /// Keychain key before returning. An interrupted destination is deleted on failure.
    public func backup(to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LedgerStoreError.backupDestinationExists
        }

        do {
            try database.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA cipher_default_page_size = 4096")
                try db.execute(sql: "VACUUM INTO ?", arguments: [destination.path])
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )

            guard var key = try keyStore.loadExistingKey() else {
                throw LedgerStoreError.encryptionKeyUnavailable
            }
            defer { key.resetBytes(in: 0..<key.count) }
            let backupDatabase = try Self.openDatabase(path: destination.path, key: key)
            defer { try? backupDatabase.close() }
            try Self.verifyIntegrity(backupDatabase)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func openDatabase(path: String, key: Data) throws -> DatabaseQueue {
        let ephemeralKey = EphemeralKey(key)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.defaultTransactionKind = .immediate
        configuration.foreignKeysEnabled = true
        configuration.prepareDatabase { db in
            try ephemeralKey.consume { key in
                try db.usePassphrase(key)
            }
            _ = try db.cipherVersion
            try db.disableCipherLogging()
            try db.execute(sql: """
                PRAGMA cipher_memory_security = ON;
                PRAGMA cipher_default_page_size = 4096;
                PRAGMA temp_store = MEMORY;
                PRAGMA journal_mode = DELETE;
                PRAGMA synchronous = EXTRA;
                PRAGMA fullfsync = ON;
                PRAGMA secure_delete = ON;
                PRAGMA foreign_keys = ON;
                """)
        }
        return try DatabaseQueue(path: path, configuration: configuration)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("operation-ledger-v1") { db in
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
                    status TEXT NOT NULL CHECK (
                        status IN ('active', 'committed', 'partiallyUndone', 'undone', 'needsRepair')
                    ),
                    createdAt DOUBLE NOT NULL,
                    updatedAt DOUBLE NOT NULL
                );

                CREATE TABLE operations (
                    id TEXT PRIMARY KEY NOT NULL,
                    batchID TEXT NOT NULL REFERENCES batches(id) ON DELETE RESTRICT,
                    ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
                    kind TEXT NOT NULL CHECK (kind IN ('move', 'undo')),
                    sourceRootID TEXT NOT NULL REFERENCES roots(id) ON DELETE RESTRICT,
                    sourceRelativePath TEXT NOT NULL CHECK (
                        length(sourceRelativePath) > 0 AND substr(sourceRelativePath, 1, 1) != '/'
                    ),
                    destinationRootID TEXT NOT NULL REFERENCES roots(id) ON DELETE RESTRICT,
                    destinationRelativePath TEXT NOT NULL CHECK (
                        length(destinationRelativePath) > 0
                        AND substr(destinationRelativePath, 1, 1) != '/'
                    ),
                    expectedSourceIdentity BLOB NOT NULL,
                    observedDestinationIdentity BLOB,
                    reversesOperationID TEXT UNIQUE
                        REFERENCES operations(id) ON DELETE RESTRICT,
                    phase TEXT NOT NULL CHECK (
                        phase IN ('prepared', 'applied', 'committed', 'aborted', 'needsRepair')
                    ),
                    createdAt DOUBLE NOT NULL,
                    updatedAt DOUBLE NOT NULL,
                    UNIQUE(batchID, ordinal)
                );

                CREATE TABLE operationEvents (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    operationID TEXT NOT NULL REFERENCES operations(id) ON DELETE RESTRICT,
                    phase TEXT NOT NULL CHECK (
                        phase IN ('prepared', 'applied', 'committed', 'aborted', 'needsRepair')
                    ),
                    timestamp DOUBLE NOT NULL,
                    errorDomain TEXT,
                    errorCode INTEGER
                );

                CREATE INDEX operationsByPhase
                    ON operations(phase, createdAt, batchID, ordinal);
                CREATE INDEX operationEventsByOperation
                    ON operationEvents(operationID, sequence);

                PRAGMA user_version = 1;
                """)
        }
        return migrator
    }

    private static func validateInverse(
        _ operation: LedgerOperationDraft,
        in db: Database
    ) throws {
        guard let reversedID = operation.reversesOperationID,
              let original = try fetchOperation(id: reversedID, from: db),
              original.draft.kind == .move,
              original.phase == .committed,
              let destinationIdentity = original.observedDestinationIdentity,
              operation.sourceRootID == original.draft.destinationRootID,
              operation.sourcePath == original.draft.destinationPath,
              operation.destinationRootID == original.draft.sourceRootID,
              operation.destinationPath == original.draft.sourcePath,
              operation.expectedSourceIdentity == destinationIdentity else {
            throw LedgerStoreError.invalidInverseOperation
        }
    }

    private static func refreshBatchStatus(
        _ batchID: String,
        in db: Database,
        at date: Date
    ) throws {
        let repairCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM operations WHERE batchID = ? AND phase = ?",
            arguments: [batchID, LedgerOperationPhase.needsRepair.rawValue]
        ) ?? 0
        let activeCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM operations WHERE batchID = ? AND phase IN (?, ?)",
            arguments: [
                batchID,
                LedgerOperationPhase.prepared.rawValue,
                LedgerOperationPhase.applied.rawValue
            ]
        ) ?? 0

        let status: LedgerBatchStatus
        if repairCount > 0 {
            status = .needsRepair
        } else if activeCount > 0 {
            status = .active
        } else {
            status = .committed
        }

        try db.execute(
            sql: "UPDATE batches SET status = ?, updatedAt = ? WHERE id = ?",
            arguments: [status.rawValue, date.timeIntervalSince1970, batchID]
        )
    }

    private static func refreshOriginalBatchStatus(
        for inverse: LedgerOperationDraft,
        in db: Database,
        at date: Date
    ) throws {
        guard let reversedID = inverse.reversesOperationID,
              let originalBatchID = try String.fetchOne(
                db,
                sql: "SELECT batchID FROM operations WHERE id = ?",
                arguments: [reversedID]
              ) else {
            throw LedgerStoreError.invalidInverseOperation
        }

        let moveCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM operations WHERE batchID = ? AND kind = 'move'",
            arguments: [originalBatchID]
        ) ?? 0
        let undoneCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM operations AS original
                WHERE original.batchID = ?
                  AND original.kind = 'move'
                  AND EXISTS (
                      SELECT 1 FROM operations AS inverse
                      WHERE inverse.reversesOperationID = original.id
                        AND inverse.kind = 'undo'
                        AND inverse.phase = 'committed'
                  )
                """,
            arguments: [originalBatchID]
        ) ?? 0

        let status: LedgerBatchStatus
        if moveCount > 0, undoneCount == moveCount {
            status = .undone
        } else if undoneCount > 0 {
            status = .partiallyUndone
        } else {
            status = .committed
        }
        try db.execute(
            sql: "UPDATE batches SET status = ?, updatedAt = ? WHERE id = ?",
            arguments: [status.rawValue, date.timeIntervalSince1970, originalBatchID]
        )
    }

    private static func insertEvent(
        _ db: Database,
        operationID: String,
        phase: LedgerOperationPhase,
        date: Date,
        errorDomain: String?,
        errorCode: Int?
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO operationEvents (
                    operationID, phase, timestamp, errorDomain, errorCode
                ) VALUES (?, ?, ?, ?, ?)
                """,
            arguments: [
                operationID,
                phase.rawValue,
                date.timeIntervalSince1970,
                errorDomain,
                errorCode
            ]
        )
    }

    private static func fetchOperation(id: String, from db: Database) throws -> LedgerOperation? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM operations WHERE id = ?",
            arguments: [id]
        ) else {
            return nil
        }
        return try decodeOperation(row)
    }

    private static func decodeOperation(_ row: Row) throws -> LedgerOperation {
        guard let kind = LedgerOperationKind(rawValue: row["kind"]),
              let phase = LedgerOperationPhase(rawValue: row["phase"]) else {
            throw LedgerStoreError.integrityCheckFailed
        }

        let expectedIdentityData: Data = row["expectedSourceIdentity"]
        let observedIdentityData: Data? = row["observedDestinationIdentity"]
        let draft = try LedgerOperationDraft(
            id: row["id"],
            batchID: row["batchID"],
            ordinal: row["ordinal"],
            kind: kind,
            sourceRootID: row["sourceRootID"],
            sourcePath: ScopedRelativePath(rawValue: row["sourceRelativePath"]),
            destinationRootID: row["destinationRootID"],
            destinationPath: ScopedRelativePath(rawValue: row["destinationRelativePath"]),
            expectedSourceIdentity: try decodeIdentity(expectedIdentityData),
            reversesOperationID: row["reversesOperationID"]
        )
        return LedgerOperation(
            draft: draft,
            phase: phase,
            observedDestinationIdentity: try observedIdentityData.map(decodeIdentity),
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
        )
    }

    private static func decodeRoot(_ row: Row) -> LedgerRootRecord {
        LedgerRootRecord(
            id: row["id"],
            bookmark: row["bookmark"],
            bookmarkVersion: row["bookmarkVersion"],
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
        )
    }

    private static func decodeEvent(_ row: Row) throws -> LedgerEvent {
        guard let phase = LedgerOperationPhase(rawValue: row["phase"]) else {
            throw LedgerStoreError.integrityCheckFailed
        }
        return LedgerEvent(
            id: row["sequence"],
            operationID: row["operationID"],
            phase: phase,
            timestamp: Date(timeIntervalSince1970: row["timestamp"]),
            errorDomain: row["errorDomain"],
            errorCode: row["errorCode"]
        )
    }

    private static func encodeIdentity(_ identity: LedgerFileIdentity) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(identity)
    }

    private static func decodeIdentity(_ data: Data) throws -> LedgerFileIdentity {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(LedgerFileIdentity.self, from: data)
    }

    private static func verifyIntegrity(_ database: DatabaseQueue) throws {
        try database.read { db in
            guard try db.cipherVersion.isEmpty == false else {
                throw LedgerStoreError.integrityCheckFailed
            }
            let quickCheck = try String.fetchAll(db, sql: "PRAGMA quick_check")
            guard quickCheck == ["ok"] else {
                throw LedgerStoreError.integrityCheckFailed
            }
            let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            guard foreignKeyFailures.isEmpty else {
                throw LedgerStoreError.integrityCheckFailed
            }
        }
    }
}

private final class EphemeralKey: @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?

    init(_ key: Data) {
        self.key = key
    }

    func consume<T>(_ body: (Data) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard var key else {
            throw LedgerStoreError.encryptionKeyUnavailable
        }
        self.key = nil
        defer { key.resetBytes(in: 0..<key.count) }
        return try body(key)
    }
}
