import Foundation
import Security

public enum DatabaseKeyStoreError: Error, Equatable, Sendable {
    case randomGenerationFailed(OSStatus)
    case keychainFailure(OSStatus)
    case invalidKeyLength
}

public protocol DatabaseKeyStore: Sendable {
    func loadOrCreateKey() throws -> Data
    func loadExistingKey() throws -> Data?
    func deleteKey() throws
}

/// Stores one nonsynchronizing, device-only 256-bit SQLCipher key in the Data Protection
/// Keychain. Queries are exact so erasing Tydly cannot remove unrelated credentials.
public struct KeychainDatabaseKeyStore: DatabaseKeyStore {
    public static let keyLength = 32

    private let service: String
    private let account: String
    private let useDataProtectionKeychain: Bool

    public init(
        service: String = "io.gymly.tydly.operation-ledger",
        account: String = "database-key-v1",
        useDataProtectionKeychain: Bool = true
    ) {
        self.service = service
        self.account = account
        self.useDataProtectionKeychain = useDataProtectionKeychain
    }

    public func loadOrCreateKey() throws -> Data {
        if let existing = try loadExistingKey() {
            return existing
        }

        var key = Data(count: Self.keyLength)
        let randomStatus = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard randomStatus == errSecSuccess else {
            key.resetBytes(in: 0..<key.count)
            throw DatabaseKeyStoreError.randomGenerationFailed(randomStatus)
        }

        var item = baseQuery
        item[kSecValueData] = key
        if useDataProtectionKeychain {
            item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        item[kSecAttrSynchronizable] = kCFBooleanFalse

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            key.resetBytes(in: 0..<key.count)
            guard let existing = try loadExistingKey() else {
                throw DatabaseKeyStoreError.keychainFailure(addStatus)
            }
            return existing
        }
        guard addStatus == errSecSuccess else {
            key.resetBytes(in: 0..<key.count)
            throw DatabaseKeyStoreError.keychainFailure(addStatus)
        }
        return key
    }

    public func loadExistingKey() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw DatabaseKeyStoreError.keychainFailure(status)
        }
        guard let key = item as? Data, key.count == Self.keyLength else {
            throw DatabaseKeyStoreError.invalidKeyLength
        }
        return key
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DatabaseKeyStoreError.keychainFailure(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        if useDataProtectionKeychain {
            query[kSecUseDataProtectionKeychain] = kCFBooleanTrue
        }
        return query
    }
}
