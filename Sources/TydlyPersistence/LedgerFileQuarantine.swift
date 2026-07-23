import Foundation

public enum LedgerFileQuarantineError: Error, Equatable, Sendable {
    case databaseNotFound
    case invalidIdentifier
}

/// Moves a closed database and any known sidecars into a private quarantine directory.
/// Callers must close the ledger first and must never resume mutations from quarantined data.
public enum LedgerFileQuarantine {
    @discardableResult
    public static func quarantineClosedDatabase(
        at databaseURL: URL,
        under quarantineRoot: URL,
        identifier: String = UUID().uuidString
    ) throws -> URL {
        guard !identifier.isEmpty,
              identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw LedgerFileQuarantineError.invalidIdentifier
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw LedgerFileQuarantineError.databaseNotFound
        }

        let destination = quarantineRoot.appendingPathComponent(identifier, isDirectory: true)
        try fileManager.createDirectory(
            at: destination,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )

        let candidates = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-journal"),
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
        for source in candidates where fileManager.fileExists(atPath: source.path) {
            try fileManager.moveItem(
                at: source,
                to: destination.appendingPathComponent(source.lastPathComponent)
            )
        }
        return destination
    }
}
