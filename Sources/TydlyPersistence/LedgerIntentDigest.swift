import CryptoKit
import Foundation
import TydlyCore

/// Canonical SHA-256 binding between an approved/promoted plan and the exact immutable
/// operation intents that the ledger will prepare.
public enum LedgerIntentDigest {
    public static func digest(
        batchID: String,
        intents: [LedgerOperationIntent]
    ) throws -> String {
        guard !batchID.isEmpty, !intents.isEmpty else {
            throw LedgerStoreError.emptyBatch
        }
        guard intents.allSatisfy({ $0.batchID == batchID }) else {
            throw LedgerStoreError.mismatchedBatch
        }

        let canonical = CanonicalBatch(
            batchID: batchID,
            operations: intents.sorted {
                if $0.ordinal == $1.ordinal {
                    return $0.id < $1.id
                }
                return $0.ordinal < $1.ordinal
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(canonical)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct CanonicalBatch: Codable {
    let batchID: String
    let operations: [LedgerOperationIntent]
}
