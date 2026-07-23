import Darwin
import Foundation
import TydlyCore
import TydlyPersistence

@main
enum LedgerCrashProbe {
    private static let crashExitCode: Int32 = 86

    static func main() async {
        guard CommandLine.arguments.count == 3 else {
            Darwin.exit(EXIT_FAILURE)
        }

        do {
            let command = CommandLine.arguments[1]
            let directory = URL(
                fileURLWithPath: CommandLine.arguments[2],
                isDirectory: true
            )
            let databaseURL = directory.appendingPathComponent("ledger.sqlite")
            let keyStore = ProbeKeyStore()

            switch command {
            case "prepare-and-crash":
                let ledger = try EncryptedOperationLedger(
                    path: databaseURL.path,
                    keyStore: keyStore
                )
                try await registerRoots(in: ledger)
                let operation = try operationDraft()
                _ = try await ledger.prepareBatch(
                    id: operation.batchID,
                    operations: [operation]
                )
                Darwin._exit(crashExitCode)

            case "verify-prepared":
                let ledger = try EncryptedOperationLedger(
                    path: databaseURL.path,
                    keyStore: keyStore
                )
                guard try await ledger.operation(id: "move-1")?.phase == .prepared else {
                    Darwin.exit(EXIT_FAILURE)
                }
                try await ledger.integrityCheck()
                try await ledger.close()
                Darwin.exit(EXIT_SUCCESS)

            case "apply-and-crash":
                let ledger = try EncryptedOperationLedger(
                    path: databaseURL.path,
                    keyStore: keyStore
                )
                try await registerRoots(in: ledger)
                let operation = try operationDraft()
                _ = try await ledger.prepareBatch(
                    id: operation.batchID,
                    operations: [operation]
                )
                _ = try await ledger.transition(
                    operationID: operation.id,
                    to: .applied,
                    observedDestinationIdentity: try destinationIdentity()
                )
                Darwin._exit(crashExitCode)

            case "verify-applied":
                let ledger = try EncryptedOperationLedger(
                    path: databaseURL.path,
                    keyStore: keyStore
                )
                guard try await ledger.operation(id: "move-1")?.phase == .applied else {
                    Darwin.exit(EXIT_FAILURE)
                }
                let action = try await ledger.reconcile(
                    operationID: "move-1",
                    observation: .matchingDestinationOnly
                )
                guard action == .markCommitted,
                      try await ledger.operation(id: "move-1")?.phase == .committed else {
                    Darwin.exit(EXIT_FAILURE)
                }
                try await ledger.integrityCheck()
                try await ledger.close()
                Darwin.exit(EXIT_SUCCESS)

            default:
                Darwin.exit(EXIT_FAILURE)
            }
        } catch {
            Darwin.exit(EXIT_FAILURE)
        }
    }

    private static func registerRoots(in ledger: EncryptedOperationLedger) async throws {
        try await ledger.registerRoot(id: "desktop", bookmark: Data("desktop".utf8))
        try await ledger.registerRoot(id: "atlas", bookmark: Data("atlas".utf8))
    }

    private static func operationDraft() throws -> LedgerOperationDraft {
        let intent = try LedgerOperationIntent(
            id: "move-1",
            batchID: "batch-1",
            ordinal: 0,
            kind: .move,
            sourceRootID: "desktop",
            sourcePath: ScopedRelativePath(rawValue: "shot.png"),
            destinationRootID: "atlas",
            destinationPath: ScopedRelativePath(rawValue: "Screens/shot.png"),
            expectedSourceIdentity: sourceIdentity()
        )
        let digest = try LedgerIntentDigest.digest(
            batchID: intent.batchID,
            intents: [intent]
        )
        return try LedgerOperationDraft(
            intent: intent,
            authorization: .userApproval(planDigest: digest)
        )
    }

    private static func sourceIdentity() throws -> LedgerFileIdentity {
        try LedgerFileIdentity(
            volumeID: "volume",
            fileID: "source",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSince1970: 1),
            fingerprint: "source-fingerprint"
        )
    }

    private static func destinationIdentity() throws -> LedgerFileIdentity {
        try LedgerFileIdentity(
            volumeID: "volume",
            fileID: "destination",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSince1970: 2),
            fingerprint: "destination-fingerprint"
        )
    }
}

private struct ProbeKeyStore: DatabaseKeyStore {
    private static let key = Data(
        repeating: 0xA5,
        count: KeychainDatabaseKeyStore.keyLength
    )

    func loadOrCreateKey() throws -> Data { Self.key }
    func loadExistingKey() throws -> Data? { Self.key }
    func deleteKey() throws {}
}
