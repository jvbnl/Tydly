import Foundation

public enum LedgerFileQuarantineError: Error, Equatable, Sendable {
    case databaseNotFound
    case invalidIdentifier
    case requiresSiblingDirectories
    case destinationExists
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

        let databaseDirectory = databaseURL.deletingLastPathComponent().standardizedFileURL
        let normalizedQuarantineRoot = quarantineRoot.standardizedFileURL
        guard databaseDirectory.deletingLastPathComponent()
                == normalizedQuarantineRoot.deletingLastPathComponent(),
              databaseDirectory != normalizedQuarantineRoot else {
            throw LedgerFileQuarantineError.requiresSiblingDirectories
        }

        let databaseDirectoryValues = try databaseDirectory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        let quarantineValues = try normalizedQuarantineRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard databaseDirectoryValues.isDirectory == true,
              databaseDirectoryValues.isSymbolicLink != true,
              quarantineValues.isDirectory == true,
              quarantineValues.isSymbolicLink != true else {
            throw LedgerFileQuarantineError.requiresSiblingDirectories
        }

        let destination = normalizedQuarantineRoot
            .appendingPathComponent(identifier, isDirectory: true)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw LedgerFileQuarantineError.destinationExists
        }

        // Sibling-directory rename keeps the complete database generation together: main
        // file, rollback journal, any unexpected sidecars, and recovery metadata.
        try fileManager.moveItem(at: databaseDirectory, to: destination)
        return destination
    }
}
