import Darwin
import Foundation
import TydlyPersistence

/// Exercises the signed app's Data Protection Keychain access without exposing key material.
/// CI invokes this on the assembled app because an unsigned XCTest host cannot carry the
/// restricted keychain entitlement.
enum SecuritySelfTest {
    static let argument = "--verify-local-security"

    static func runIfRequested() {
        guard CommandLine.arguments.contains(argument) else {
            return
        }

        let store = KeychainDatabaseKeyStore(
            service: "io.gymly.tydly.security-self-test.\(UUID().uuidString)",
            account: "ephemeral-key"
        )
        do {
            defer { try? store.deleteKey() }
            let first = try store.loadOrCreateKey()
            let second = try store.loadOrCreateKey()
            guard first.count == KeychainDatabaseKeyStore.keyLength, first == second else {
                throw DatabaseKeyStoreError.invalidKeyLength
            }
            try store.deleteKey()
            guard try store.loadExistingKey() == nil else {
                throw DatabaseKeyStoreError.invalidKeyLength
            }
            Darwin.exit(EXIT_SUCCESS)
        } catch {
            fputs("Tydly local security self-test failed.\n", stderr)
            Darwin.exit(EXIT_FAILURE)
        }
    }
}
