import CryptoKit
import Foundation
import TydlyCore

/// Issues and verifies opaque authorization receipts bound to the encrypted ledger key and
/// the exact canonical batch intent. Serialized callers can recompute a digest, but cannot
/// forge the HMAC without the nonsynchronizing Keychain key.
public struct LedgerAuthorizationAuthenticator: Sendable {
    private let keyStore: any DatabaseKeyStore

    public init(keyStore: any DatabaseKeyStore) {
        self.keyStore = keyStore
    }

    public func authorizeUserApproval(
        batchID: String,
        intents: [LedgerOperationIntent],
        executionAuthorization: ExecutionAuthorization
    ) throws -> LedgerAuthorization {
        guard executionAuthorization.kind == .approvedByUser else {
            throw LedgerStoreError.authorizationNotGranted
        }
        let digest = try LedgerIntentDigest.digest(batchID: batchID, intents: intents)
        let payload = AuthorizationPayload(
            kind: "userApproval",
            batchID: batchID,
            intentDigest: digest,
            ruleID: nil,
            ruleRevision: nil
        )
        return .userApproval(
            planDigest: digest,
            authenticationTag: try authenticationTag(for: payload)
        )
    }

    public func authorizePromotedRule(
        batchID: String,
        intents: [LedgerOperationIntent],
        executionAuthorization: ExecutionAuthorization
    ) throws -> LedgerAuthorization {
        guard case .approvedByPromotedRule(let ruleID, let revision)
                = executionAuthorization.kind else {
            throw LedgerStoreError.authorizationNotGranted
        }
        let digest = try LedgerIntentDigest.digest(batchID: batchID, intents: intents)
        let payload = AuthorizationPayload(
            kind: "promotedRule",
            batchID: batchID,
            intentDigest: digest,
            ruleID: ruleID,
            ruleRevision: revision
        )
        return .promotedRule(
            ruleID: ruleID,
            revision: revision,
            intentDigest: digest,
            authenticationTag: try authenticationTag(for: payload)
        )
    }

    func verify(
        _ authorization: LedgerAuthorization,
        batchID: String,
        intents: [LedgerOperationIntent]
    ) throws -> Bool {
        let digest = try LedgerIntentDigest.digest(batchID: batchID, intents: intents)
        guard authorization.intentDigest == digest else {
            return false
        }

        let payload: AuthorizationPayload
        switch authorization {
        case .userApproval:
            payload = AuthorizationPayload(
                kind: "userApproval",
                batchID: batchID,
                intentDigest: digest,
                ruleID: nil,
                ruleRevision: nil
            )
        case .promotedRule(let ruleID, let revision, _, _):
            payload = AuthorizationPayload(
                kind: "promotedRule",
                batchID: batchID,
                intentDigest: digest,
                ruleID: ruleID,
                ruleRevision: revision
            )
        }

        guard var key = try keyStore.loadExistingKey() else {
            throw LedgerStoreError.encryptionKeyUnavailable
        }
        defer { key.resetBytes(in: 0..<key.count) }
        let authenticationKey = Self.derivedAuthenticationKey(from: key)
        return HMAC<SHA256>.isValidAuthenticationCode(
            authorization.authenticationTag,
            authenticating: try Self.encode(payload),
            using: authenticationKey
        )
    }

    private func authenticationTag(for payload: AuthorizationPayload) throws -> Data {
        guard var key = try keyStore.loadExistingKey() else {
            throw LedgerStoreError.encryptionKeyUnavailable
        }
        defer { key.resetBytes(in: 0..<key.count) }
        let authenticationKey = Self.derivedAuthenticationKey(from: key)
        return Data(
            HMAC<SHA256>.authenticationCode(
                for: try Self.encode(payload),
                using: authenticationKey
            )
        )
    }

    private static func derivedAuthenticationKey(from databaseKey: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: databaseKey),
            salt: Data("Tydly ledger authorization v1".utf8),
            info: Data("batch-intent HMAC".utf8),
            outputByteCount: 32
        )
    }

    private static func encode(_ payload: AuthorizationPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }
}

private struct AuthorizationPayload: Codable {
    let kind: String
    let batchID: String
    let intentDigest: String
    let ruleID: String?
    let ruleRevision: Int?
}
