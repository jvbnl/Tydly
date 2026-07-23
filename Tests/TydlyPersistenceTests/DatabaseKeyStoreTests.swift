import Foundation
import XCTest
import TydlyPersistence

final class DatabaseKeyStoreTests: XCTestCase {
    func testKeychainKeyIsStableUntilExactDeletion() throws {
        let store = KeychainDatabaseKeyStore(
            service: "io.gymly.tydly.tests.\(UUID().uuidString)",
            account: "ledger-key"
        )
        defer { try? store.deleteKey() }

        XCTAssertNil(try store.loadExistingKey())
        let first = try store.loadOrCreateKey()
        let second = try store.loadOrCreateKey()

        XCTAssertEqual(first.count, KeychainDatabaseKeyStore.keyLength)
        XCTAssertEqual(first, second)

        try store.deleteKey()
        XCTAssertNil(try store.loadExistingKey())
    }
}
