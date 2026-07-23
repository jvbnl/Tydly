import Foundation
import Darwin
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
    case insecureStorageDirectory
    case rootMutationRejected
    case rootGenerationNotFound
    case rootBindingMismatch
    case rootGenerationConflict
    case rootBindingConflict
    case destinationIdentityIsImmutable
    case invalidBatchComposition
    case missingRepairReason
    case activeResourceConflict
    case synchronizationFailed(Int32)
    case authorizationDigestMismatch
    case authorizationNotGranted
    case authorizationTagInvalid
    case repairRequired
}

public struct LedgerRootRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let descriptor: RootGenerationDescriptor
    public let bookmark: Data
    public let bookmarkVersion: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        descriptor: RootGenerationDescriptor,
        bookmark: Data,
        bookmarkVersion: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = descriptor.id
        self.descriptor = descriptor
        self.bookmark = bookmark
        self.bookmarkVersion = bookmarkVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct RootBindingRecord: Identifiable, Equatable, Sendable {
    public let id: String
    public let activeRootID: String
    public let purpose: RootPurpose
    public let status: RootBindingStatus
    public let updatedAt: Date

    public init(
        id: String,
        activeRootID: String,
        purpose: RootPurpose,
        status: RootBindingStatus,
        updatedAt: Date
    ) {
        self.id = id
        self.activeRootID = activeRootID
        self.purpose = purpose
        self.status = status
        self.updatedAt = updatedAt
    }
}

public struct RootBindingSnapshot: Equatable, Sendable {
    public let revision: Int
    public let bindings: [RootBindingRecord]

    public init(revision: Int, bindings: [RootBindingRecord]) {
        self.revision = revision
        self.bindings = bindings
    }
}

public struct RootGenerationRegistration: Sendable {
    public let descriptor: RootGenerationDescriptor
    public let bookmark: Data
    public let bookmarkVersion: Int
    public let status: RootBindingStatus

    public init(
        descriptor: RootGenerationDescriptor,
        bookmark: Data,
        bookmarkVersion: Int = 1,
        status: RootBindingStatus = .active
    ) {
        self.descriptor = descriptor
        self.bookmark = bookmark
        self.bookmarkVersion = bookmarkVersion
        self.status = status
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
        let databaseExisted = FileManager.default.fileExists(atPath: path)
        try Self.preparePrivateDirectory(databaseURL.deletingLastPathComponent())

        var key: Data
        if databaseExisted {
            guard let existingKey = try keyStore.loadExistingKey() else {
                throw LedgerStoreError.encryptionKeyUnavailable
            }
            key = existingKey
        } else {
            key = try keyStore.loadOrCreateKey()
        }
        defer { key.resetBytes(in: 0..<key.count) }
        database = try Self.openDatabase(path: path, key: key)
        if databaseExisted {
            try Self.verifyPhysicalIntegrity(database)
        }
        try Self.migrator.migrate(database)
        try Self.verifyIntegrity(database)
        try Self.verifyAuthorizationIntegrity(database, keyStore: keyStore)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: path
        )
        try Self.verifyPrivatePermissions(at: databaseURL, allowedMask: 0o600)
    }

    public func close() throws {
        try database.close()
    }

    package func registerRoot(
        id: String,
        bookmark: Data,
        bookmarkVersion: Int = 1,
        at date: Date = Date()
    ) throws {
        if try root(id: id) != nil {
            throw LedgerStoreError.rootMutationRejected
        }
        let descriptor = try RootGenerationDescriptor(
            id: id,
            logicalRootID: id,
            generation: 0,
            purpose: .legacy,
            displayName: id,
            identity: RootResourceIdentity(volumeID: "legacy", fileID: id)
        )
        try registerRootGeneration(
            descriptor,
            bookmark: bookmark,
            bookmarkVersion: bookmarkVersion,
            status: .active,
            at: date
        )
    }

    package func registerRootGeneration(
        _ descriptor: RootGenerationDescriptor,
        bookmark: Data,
        bookmarkVersion: Int = 1,
        status: RootBindingStatus = .active,
        at date: Date = Date()
    ) throws {
        try registerRootGenerations(
            [
                RootGenerationRegistration(
                    descriptor: descriptor,
                    bookmark: bookmark,
                    bookmarkVersion: bookmarkVersion,
                    status: status
                )
            ],
            at: date
        )
    }

    package func registerRootGenerations(
        _ registrations: [RootGenerationRegistration],
        expectedRootSetRevision: Int? = nil,
        replacingLegacyBindings: Bool = false,
        at date: Date = Date()
    ) throws {
        guard !registrations.isEmpty,
              registrations.allSatisfy({ !$0.bookmark.isEmpty }),
              Set(registrations.map(\.descriptor.id)).count == registrations.count else {
            throw LedgerValidationError.emptyIdentifier
        }

        try database.write { db in
            let currentRevision = try Int.fetchOne(
                db,
                sql: "SELECT revision FROM rootSetState WHERE id = 1"
            ) ?? 0
            if let expectedRootSetRevision,
               expectedRootSetRevision != currentRevision {
                throw LedgerStoreError.rootBindingConflict
            }
            if replacingLegacyBindings {
                let referencedLegacyCount = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*)
                        FROM roots
                        WHERE purpose = 'legacy'
                          AND (
                              EXISTS (
                                  SELECT 1 FROM operations
                                  WHERE sourceRootID = roots.id
                                     OR destinationRootID = roots.id
                              )
                          )
                        """
                ) ?? 0
                guard referencedLegacyCount == 0 else {
                    throw LedgerStoreError.repairRequired
                }
                try db.execute(sql: """
                    DELETE FROM rootBindings WHERE purpose = 'legacy';
                    DELETE FROM roots WHERE purpose = 'legacy';
                    """)
            }
            for registration in registrations.sorted(by: {
                if $0.descriptor.logicalRootID == $1.descriptor.logicalRootID {
                    return $0.descriptor.generation < $1.descriptor.generation
                }
                return $0.descriptor.logicalRootID < $1.descriptor.logicalRootID
            }) {
                try Self.registerRootGeneration(registration, in: db, at: date)
            }
            try db.execute(
                sql: "UPDATE rootSetState SET revision = revision + 1 WHERE id = 1"
            )
        }
    }

    private static func registerRootGeneration(
        _ registration: RootGenerationRegistration,
        in db: Database,
        at date: Date
    ) throws {
        let descriptor = registration.descriptor
        if let existing = try Row.fetchOne(
                db,
                sql: "SELECT * FROM roots WHERE id = ?",
                arguments: [descriptor.id]
            ) {
                let record = try Self.decodeRoot(existing)
                guard record.descriptor == descriptor,
                      record.bookmark == registration.bookmark,
                      record.bookmarkVersion == registration.bookmarkVersion else {
                    throw LedgerStoreError.rootMutationRejected
                }
                if let activeRootID = try String.fetchOne(
                    db,
                    sql: """
                        SELECT activeRootID FROM rootBindings
                        WHERE logicalRootID = ?
                        """,
                    arguments: [descriptor.logicalRootID]
                ), activeRootID != descriptor.id {
                    throw LedgerStoreError.rootGenerationConflict
                }
            } else {
                let maximumGeneration = try Int.fetchOne(
                    db,
                    sql: "SELECT MAX(generation) FROM roots WHERE logicalRootID = ?",
                    arguments: [descriptor.logicalRootID]
                )
                guard descriptor.generation == (maximumGeneration.map { $0 + 1 } ?? 0) else {
                    throw LedgerStoreError.rootGenerationConflict
                }
                try db.execute(
                    sql: """
                        INSERT INTO roots (
                            id, bookmark, bookmarkVersion,
                            logicalRootID, generation, purpose, displayName,
                            volumeID, resourceID, createdAt, updatedAt
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        descriptor.id,
                        registration.bookmark,
                        registration.bookmarkVersion,
                        descriptor.logicalRootID,
                        descriptor.generation,
                        descriptor.purpose.rawValue,
                        descriptor.displayName,
                        descriptor.identity.volumeID,
                        descriptor.identity.fileID,
                        date.timeIntervalSince1970,
                        date.timeIntervalSince1970
                    ]
                )
        }
        if let binding = try Row.fetchOne(
                db,
                sql: "SELECT purpose FROM rootBindings WHERE logicalRootID = ?",
                arguments: [descriptor.logicalRootID]
            ) {
                let purposeRaw: String = binding["purpose"]
                guard purposeRaw == descriptor.purpose.rawValue else {
                    throw LedgerStoreError.rootBindingMismatch
                }
        }
        try db.execute(
                sql: """
                    INSERT INTO rootBindings (
                        logicalRootID, activeRootID, purpose, status, updatedAt
                    ) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(logicalRootID) DO UPDATE SET
                        activeRootID = excluded.activeRootID,
                        purpose = excluded.purpose,
                        status = excluded.status,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [
                    descriptor.logicalRootID,
                    descriptor.id,
                    descriptor.purpose.rawValue,
                    registration.status.rawValue,
                    date.timeIntervalSince1970
                ]
        )
    }

    package func updateRootBindingStatus(
        logicalRootID: String,
        expectedActiveRootID: String,
        status: RootBindingStatus,
        at date: Date = Date()
    ) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE rootBindings SET status = ?, updatedAt = ?
                    WHERE logicalRootID = ? AND activeRootID = ?
                    """,
                arguments: [
                    status.rawValue,
                    date.timeIntervalSince1970,
                    logicalRootID,
                    expectedActiveRootID
                ]
            )
            guard db.changesCount == 1 else {
                throw LedgerStoreError.rootGenerationNotFound
            }
            try db.execute(
                sql: "UPDATE rootSetState SET revision = revision + 1 WHERE id = 1"
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
            return try Self.decodeRoot(row)
        }
    }

    public func rootBinding(logicalRootID: String) throws -> RootBindingRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM rootBindings WHERE logicalRootID = ?",
                arguments: [logicalRootID]
            ) else {
                return nil
            }
            return try Self.decodeRootBinding(row)
        }
    }

    public func rootBindings() throws -> [RootBindingRecord] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM rootBindings ORDER BY logicalRootID"
            ).map(Self.decodeRootBinding)
        }
    }

    public func rootBindingSnapshot() throws -> RootBindingSnapshot {
        try database.read { db in
            let revision = try Int.fetchOne(
                db,
                sql: "SELECT revision FROM rootSetState WHERE id = 1"
            ) ?? 0
            let bindings = try Row.fetchAll(
                db,
                sql: "SELECT * FROM rootBindings ORDER BY logicalRootID"
            ).map(Self.decodeRootBinding)
            return RootBindingSnapshot(revision: revision, bindings: bindings)
        }
    }

    public func activeRoot(logicalRootID: String) throws -> LedgerRootRecord? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT roots.*
                    FROM rootBindings
                    JOIN roots ON roots.id = rootBindings.activeRootID
                    WHERE rootBindings.logicalRootID = ?
                    """,
                arguments: [logicalRootID]
            ) else {
                return nil
            }
            return try Self.decodeRoot(row)
        }
    }

    public func rootGenerations(logicalRootID: String) throws -> [LedgerRootRecord] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM roots
                    WHERE logicalRootID = ?
                    ORDER BY generation
                    """,
                arguments: [logicalRootID]
            ).map(Self.decodeRoot)
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
        guard Set(operations.map(\.kind)).count == 1 else {
            throw LedgerStoreError.invalidBatchComposition
        }
        let intents = operations.map(\.intent)
        let intentDigest = try LedgerIntentDigest.digest(
            batchID: id,
            intents: intents
        )
        guard operations.allSatisfy({ $0.authorization.intentDigest == intentDigest }) else {
            throw LedgerStoreError.authorizationDigestMismatch
        }
        let authenticator = LedgerAuthorizationAuthenticator(keyStore: keyStore)
        for operation in operations {
            guard try authenticator.verify(
                operation.authorization,
                batchID: id,
                intents: intents
            ) else {
                throw LedgerStoreError.authorizationTagInvalid
            }
        }

        return try database.write { db in
            let repairCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM operations WHERE phase = 'needsRepair'"
            ) ?? 0
            guard repairCount == 0 else {
                throw LedgerStoreError.repairRequired
            }
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
                try Self.validateNoActiveResourceConflict(operation, in: db)
                let expectedIdentity = try Self.encodeIdentity(operation.expectedSourceIdentity)
                let authorization = try Self.encodeAuthorization(operation.authorization)
                try db.execute(
                    sql: """
                        INSERT INTO operations (
                            id, batchID, ordinal, kind,
                            sourceRootID, sourceRelativePath,
                            destinationRootID, destinationRelativePath,
                            expectedSourceIdentity, observedDestinationIdentity,
                            reversesOperationID, authorization, phase, repairReason,
                            createdAt, updatedAt
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, NULL, ?, ?)
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
                        authorization,
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
        repairReason: LedgerRepairReason? = nil,
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
                guard current.observedDestinationIdentity == nil,
                      let observedDestinationIdentity else {
                    throw LedgerStoreError.missingDestinationIdentity
                }
                resultingIdentity = observedDestinationIdentity
            } else {
                guard observedDestinationIdentity == nil else {
                    throw LedgerStoreError.destinationIdentityIsImmutable
                }
                resultingIdentity = current.observedDestinationIdentity
            }
            if nextPhase == .committed, current.draft.kind == .undo {
                guard let reversedID = current.draft.reversesOperationID,
                      let original = try Self.fetchOperation(id: reversedID, from: db),
                      resultingIdentity == original.draft.expectedSourceIdentity else {
                    throw LedgerStoreError.invalidInverseOperation
                }
            }

            let resultingRepairReason: LedgerRepairReason?
            if nextPhase == .needsRepair {
                guard let repairReason else {
                    throw LedgerStoreError.missingRepairReason
                }
                resultingRepairReason = repairReason
            } else {
                resultingRepairReason = nil
            }

            let encodedIdentity = try resultingIdentity.map(Self.encodeIdentity)
            try db.execute(
                sql: """
                    UPDATE operations
                    SET phase = ?, observedDestinationIdentity = ?, repairReason = ?, updatedAt = ?
                    WHERE id = ? AND phase = ?
                    """,
                arguments: [
                    nextPhase.rawValue,
                    encodedIdentity,
                    resultingRepairReason?.rawValue,
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
            if current.draft.kind == .undo {
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
        if current.phase == .committed,
           current.draft.kind == .move,
           observation == .matchingSourceOnly,
           try hasCommittedInverse(for: operationID) {
            return .none
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
        case .holdForRepair(let reason):
            if reason == .capabilityUnavailable {
                try database.write { db in
                    try Self.insertEvent(
                        db,
                        operationID: operationID,
                        phase: current.phase,
                        date: date,
                        errorDomain: reason.rawValue,
                        errorCode: nil
                    )
                }
            } else if current.phase != .needsRepair {
                _ = try transition(
                    operationID: operationID,
                    to: .needsRepair,
                    repairReason: reason,
                    at: date
                )
            }
        case .retryMutation, .none:
            break
        }
        return action
    }

    private func hasCommittedInverse(for operationID: String) throws -> Bool {
        try database.read { db in
            (try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM operations
                    WHERE reversesOperationID = ? AND kind = 'undo' AND phase = 'committed'
                    """,
                arguments: [operationID]
            ) ?? 0) > 0
        }
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

    public func operationsNeedingRepair() throws -> [LedgerOperation] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM operations
                    WHERE phase = 'needsRepair'
                    ORDER BY updatedAt, batchID, ordinal
                    """
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
        try Self.verifyAuthorizationIntegrity(database, keyStore: keyStore)
    }

    public func schemaVersion() throws -> Int {
        try database.read { db in
            try Self.migrator.appliedMigrations(db).count
        }
    }

    /// Creates a compact, consistently encrypted snapshot and verifies it with the same
    /// Keychain key before returning. An interrupted destination is deleted on failure.
    public func backup(to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw LedgerStoreError.backupDestinationExists
        }
        let temporary = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).partial-\(UUID().uuidString)")

        do {
            try database.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA cipher_default_page_size = 4096")
                try db.execute(sql: "VACUUM INTO ?", arguments: [temporary.path])
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporary.path
            )
            try Self.verifyPrivatePermissions(at: temporary, allowedMask: 0o600)

            guard var key = try keyStore.loadExistingKey() else {
                throw LedgerStoreError.encryptionKeyUnavailable
            }
            defer { key.resetBytes(in: 0..<key.count) }
            let backupDatabase = try Self.openDatabase(path: temporary.path, key: key)
            defer { try? backupDatabase.close() }
            try Self.verifyIntegrity(backupDatabase)
            try Self.verifyAuthorizationIntegrity(backupDatabase, keyStore: keyStore)

            try backupDatabase.close()
            try Self.synchronizeFile(at: temporary)
            try FileManager.default.moveItem(at: temporary, to: destination)
            try Self.synchronizeDirectory(at: destination.deletingLastPathComponent())
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func openDatabase(path: String, key: Data) throws -> DatabaseQueue {
        let ephemeralKey = EphemeralKey(key)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
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
                        status IN (
                            'active', 'committed', 'aborted',
                            'partiallyUndone', 'undone', 'needsRepair'
                        )
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
                    reversesOperationID TEXT
                        REFERENCES operations(id) ON DELETE RESTRICT,
                    authorization BLOB NOT NULL,
                    phase TEXT NOT NULL CHECK (
                        phase IN ('prepared', 'applied', 'committed', 'aborted', 'needsRepair')
                    ),
                    repairReason TEXT CHECK (
                        repairReason IS NULL OR repairReason IN (
                            'ambiguousPresence',
                            'missingCommittedItem',
                            'destinationConflict',
                            'capabilityUnavailable',
                            'terminalStateMismatch'
                        )
                    ),
                    createdAt DOUBLE NOT NULL,
                    updatedAt DOUBLE NOT NULL,
                    CHECK (
                        (kind = 'move' AND reversesOperationID IS NULL)
                        OR (kind = 'undo' AND reversesOperationID IS NOT NULL)
                    ),
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
                CREATE UNIQUE INDEX oneLiveUndoPerOperation
                    ON operations(reversesOperationID)
                    WHERE reversesOperationID IS NOT NULL AND phase != 'aborted';
                CREATE UNIQUE INDEX oneActiveSource
                    ON operations(sourceRootID, sourceRelativePath)
                    WHERE phase IN ('prepared', 'applied', 'needsRepair');
                CREATE UNIQUE INDEX oneActiveDestination
                    ON operations(destinationRootID, destinationRelativePath)
                    WHERE phase IN ('prepared', 'applied', 'needsRepair');

                """)
        }
        migrator.registerMigration("root-capability-generations-v2") { db in
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
                SET logicalRootID = id,
                    displayName = id,
                    resourceID = id
                WHERE logicalRootID = '';

                CREATE UNIQUE INDEX rootGenerationByLogicalID
                    ON roots(logicalRootID, generation);

                CREATE TABLE rootBindings (
                    logicalRootID TEXT PRIMARY KEY NOT NULL,
                    activeRootID TEXT NOT NULL UNIQUE
                        REFERENCES roots(id) ON DELETE RESTRICT,
                    purpose TEXT NOT NULL CHECK (
                        purpose IN (
                            'sourceDesktop',
                            'sourceDownloads',
                            'destination',
                            'legacy'
                        )
                    ),
                    status TEXT NOT NULL CHECK (
                        status IN ('active', 'needsReauthorization', 'unsupported')
                    ),
                    updatedAt DOUBLE NOT NULL
                );

                CREATE TABLE rootSetState (
                    id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                    revision INTEGER NOT NULL CHECK (revision >= 0)
                );
                INSERT INTO rootSetState (id, revision) VALUES (1, 0);

                INSERT INTO rootBindings (
                    logicalRootID, activeRootID, purpose, status, updatedAt
                )
                SELECT logicalRootID, id, purpose, 'needsReauthorization', updatedAt
                FROM roots;
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

    private static func validateNoActiveResourceConflict(
        _ operation: LedgerOperationDraft,
        in db: Database
    ) throws {
        let conflictCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM operations
                WHERE phase IN ('prepared', 'applied', 'needsRepair')
                  AND (
                      (sourceRootID = ? AND sourceRelativePath = ?)
                      OR (destinationRootID = ? AND destinationRelativePath = ?)
                      OR (sourceRootID = ? AND sourceRelativePath = ?)
                      OR (destinationRootID = ? AND destinationRelativePath = ?)
                  )
                """,
            arguments: [
                operation.sourceRootID,
                operation.sourcePath.rawValue,
                operation.sourceRootID,
                operation.sourcePath.rawValue,
                operation.destinationRootID,
                operation.destinationPath.rawValue,
                operation.destinationRootID,
                operation.destinationPath.rawValue
            ]
        ) ?? 0
        guard conflictCount == 0 else {
            throw LedgerStoreError.activeResourceConflict
        }
    }

    private static func refreshBatchStatus(
        _ batchID: String,
        in db: Database,
        at date: Date
    ) throws {
        guard let kindRaw = try String.fetchOne(
            db,
            sql: "SELECT kind FROM operations WHERE batchID = ? LIMIT 1",
            arguments: [batchID]
        ), let kind = LedgerOperationKind(rawValue: kindRaw) else {
            throw LedgerStoreError.integrityCheckFailed
        }

        let ownRepairCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM operations WHERE batchID = ? AND phase = 'needsRepair'",
            arguments: [batchID]
        ) ?? 0
        let inverseRepairCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*)
                FROM operations AS inverse
                JOIN operations AS original
                  ON inverse.reversesOperationID = original.id
                WHERE original.batchID = ? AND inverse.phase = 'needsRepair'
                """,
            arguments: [batchID]
        ) ?? 0
        let activeCount = try Int.fetchOne(
            db,
            sql: """
                SELECT COUNT(*) FROM operations
                WHERE batchID = ? AND phase IN ('prepared', 'applied')
                """,
            arguments: [batchID]
        ) ?? 0
        let committedCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM operations WHERE batchID = ? AND phase = 'committed'",
            arguments: [batchID]
        ) ?? 0

        let status: LedgerBatchStatus
        if ownRepairCount > 0 || inverseRepairCount > 0 {
            status = .needsRepair
        } else if activeCount > 0 {
            status = .active
        } else if committedCount == 0 {
            status = .aborted
        } else if kind == .undo {
            status = .committed
        } else {
            let reversedCount = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM operations AS original
                    WHERE original.batchID = ?
                      AND original.kind = 'move'
                      AND original.phase = 'committed'
                      AND EXISTS (
                          SELECT 1 FROM operations AS inverse
                          WHERE inverse.reversesOperationID = original.id
                            AND inverse.kind = 'undo'
                            AND inverse.phase = 'committed'
                      )
                    """,
                arguments: [batchID]
            ) ?? 0
            if reversedCount == committedCount {
                status = .undone
            } else if reversedCount > 0 {
                status = .partiallyUndone
            } else {
                status = .committed
            }
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
        try refreshBatchStatus(originalBatchID, in: db, at: date)
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
        let authorizationData: Data = row["authorization"]
        let repairReasonRaw: String? = row["repairReason"]
        let repairReason = repairReasonRaw.flatMap(LedgerRepairReason.init(rawValue:))
        if repairReasonRaw != nil, repairReason == nil {
            throw LedgerStoreError.integrityCheckFailed
        }
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
            reversesOperationID: row["reversesOperationID"],
            authorization: try decodeAuthorization(authorizationData)
        )
        return LedgerOperation(
            draft: draft,
            phase: phase,
            observedDestinationIdentity: try observedIdentityData.map(decodeIdentity),
            repairReason: repairReason,
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
        )
    }

    private static func decodeRoot(_ row: Row) throws -> LedgerRootRecord {
        let purposeRaw: String = row["purpose"]
        guard let purpose = RootPurpose(rawValue: purposeRaw) else {
            throw LedgerStoreError.integrityCheckFailed
        }
        let identity = try RootResourceIdentity(
            volumeID: row["volumeID"],
            fileID: row["resourceID"]
        )
        let descriptor = try RootGenerationDescriptor(
            id: row["id"],
            logicalRootID: row["logicalRootID"],
            generation: row["generation"],
            purpose: purpose,
            displayName: row["displayName"],
            identity: identity
        )
        return LedgerRootRecord(
            descriptor: descriptor,
            bookmark: row["bookmark"],
            bookmarkVersion: row["bookmarkVersion"],
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
        )
    }

    private static func decodeRootBinding(_ row: Row) throws -> RootBindingRecord {
        let purposeRaw: String = row["purpose"]
        let statusRaw: String = row["status"]
        guard let purpose = RootPurpose(rawValue: purposeRaw),
              let status = RootBindingStatus(rawValue: statusRaw) else {
            throw LedgerStoreError.integrityCheckFailed
        }
        return RootBindingRecord(
            id: row["logicalRootID"],
            activeRootID: row["activeRootID"],
            purpose: purpose,
            status: status,
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

    private static func encodeAuthorization(_ authorization: LedgerAuthorization) throws -> Data {
        try JSONEncoder().encode(authorization)
    }

    private static func decodeAuthorization(_ data: Data) throws -> LedgerAuthorization {
        try JSONDecoder().decode(LedgerAuthorization.self, from: data)
    }

    private static func preparePrivateDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw LedgerStoreError.insecureStorageDirectory
            }
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw LedgerStoreError.insecureStorageDirectory
            }
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try verifyPrivatePermissions(at: directory, allowedMask: 0o700)
    }

    private static func verifyPrivatePermissions(at url: URL, allowedMask: Int) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0,
              permissions.intValue & allowedMask == allowedMask else {
            throw LedgerStoreError.insecureStorageDirectory
        }
    }

    private static func synchronizeFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw LedgerStoreError.synchronizationFailed(errno)
        }
        defer { Darwin.close(descriptor) }
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else {
            throw LedgerStoreError.synchronizationFailed(errno)
        }
    }

    private static func synchronizeDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw LedgerStoreError.synchronizationFailed(errno)
        }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw LedgerStoreError.synchronizationFailed(errno)
        }
    }

    private static func verifyPhysicalIntegrity(_ database: DatabaseQueue) throws {
        try database.read { db in
            guard try db.cipherVersion.isEmpty == false else {
                throw LedgerStoreError.integrityCheckFailed
            }
            let integrityCheck = try String.fetchAll(db, sql: "PRAGMA integrity_check")
            guard integrityCheck == ["ok"] else {
                throw LedgerStoreError.integrityCheckFailed
            }
            let foreignKeyFailures = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
            guard foreignKeyFailures.isEmpty else {
                throw LedgerStoreError.integrityCheckFailed
            }
        }
    }

    private static func verifyIntegrity(_ database: DatabaseQueue) throws {
        try verifyPhysicalIntegrity(database)
        try database.read { db in
            let roots = try Row.fetchAll(db, sql: "SELECT * FROM roots")
                .map(Self.decodeRoot)
            guard let rootSetRevision = try Int.fetchOne(
                db,
                sql: "SELECT revision FROM rootSetState WHERE id = 1"
            ), rootSetRevision >= 0 else {
                throw LedgerStoreError.integrityCheckFailed
            }
            let rootsByID = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
            let bindings = try Row.fetchAll(db, sql: "SELECT * FROM rootBindings")
                .map(Self.decodeRootBinding)
            for binding in bindings {
                guard let root = rootsByID[binding.activeRootID],
                      root.descriptor.logicalRootID == binding.id,
                      root.descriptor.purpose == binding.purpose else {
                    throw LedgerStoreError.integrityCheckFailed
                }
                let maximumGeneration = roots
                    .filter { $0.descriptor.logicalRootID == binding.id }
                    .map(\.descriptor.generation)
                    .max()
                guard let maximumGeneration,
                      root.descriptor.generation == maximumGeneration else {
                    throw LedgerStoreError.integrityCheckFailed
                }
            }

            let rows = try Row.fetchAll(db, sql: "SELECT * FROM operations")
            for row in rows {
                let operation = try decodeOperation(row)
                if operation.phase == .needsRepair {
                    guard operation.repairReason != nil else {
                        throw LedgerStoreError.integrityCheckFailed
                    }
                } else if operation.repairReason != nil {
                    throw LedgerStoreError.integrityCheckFailed
                }

                let lastEventPhase = try String.fetchOne(
                    db,
                    sql: """
                        SELECT phase FROM operationEvents
                        WHERE operationID = ?
                        ORDER BY sequence DESC
                        LIMIT 1
                        """,
                    arguments: [operation.id]
                )
                guard lastEventPhase == operation.phase.rawValue else {
                    throw LedgerStoreError.integrityCheckFailed
                }
            }
        }
    }

    private static func verifyAuthorizationIntegrity(
        _ database: DatabaseQueue,
        keyStore: any DatabaseKeyStore
    ) throws {
        let batches = try database.read { db -> [[LedgerOperation]] in
            let operations = try Row.fetchAll(db, sql: "SELECT * FROM operations")
                .map(Self.decodeOperation)
            return Dictionary(grouping: operations, by: \.draft.batchID)
                .values
                .map { Array($0) }
        }
        let authenticator = LedgerAuthorizationAuthenticator(keyStore: keyStore)
        for batch in batches {
            guard let batchID = batch.first?.draft.batchID else { continue }
            let intents = batch.map(\.draft.intent)
            for operation in batch {
                guard try authenticator.verify(
                    operation.draft.authorization,
                    batchID: batchID,
                    intents: intents
                ) else {
                    throw LedgerStoreError.authorizationTagInvalid
                }
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
