import Foundation
import XCTest
import TydlyPersistence

final class LedgerFileQuarantineTests: XCTestCase {
    func testQuarantineMovesDatabaseAndKnownSidecarsWithoutDeletingThem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TydlyQuarantineTests-\(UUID().uuidString)", isDirectory: true)
        let quarantineRoot = root.appendingPathComponent("Quarantine", isDirectory: true)
        let database = root.appendingPathComponent("ledger.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: quarantineRoot,
            withIntermediateDirectories: false
        )
        for url in [
            database,
            URL(fileURLWithPath: database.path + "-journal"),
            URL(fileURLWithPath: database.path + "-wal"),
            URL(fileURLWithPath: database.path + "-shm")
        ] {
            try Data(url.lastPathComponent.utf8).write(to: url)
        }

        let destination = try LedgerFileQuarantine.quarantineClosedDatabase(
            at: database,
            under: quarantineRoot,
            identifier: "corrupt-store-1"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path))
        XCTAssertEqual(
            try Set(FileManager.default.contentsOfDirectory(atPath: destination.path)),
            Set([
                "ledger.sqlite",
                "ledger.sqlite-journal",
                "ledger.sqlite-wal",
                "ledger.sqlite-shm"
            ])
        )
    }

    func testQuarantineRejectsUnsafeIdentifier() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TydlyQuarantineTests-\(UUID().uuidString)", isDirectory: true)
        let quarantineRoot = root.appendingPathComponent("Quarantine", isDirectory: true)
        let database = root.appendingPathComponent("ledger.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(
            at: quarantineRoot,
            withIntermediateDirectories: false
        )
        try Data().write(to: database)

        XCTAssertThrowsError(
            try LedgerFileQuarantine.quarantineClosedDatabase(
                at: database,
                under: quarantineRoot,
                identifier: "../escape"
            )
        ) {
            XCTAssertEqual($0 as? LedgerFileQuarantineError, .invalidIdentifier)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.path))
    }
}
