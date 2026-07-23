import Foundation

public enum LedgerValidationError: Error, Equatable, Sendable {
    case emptyIdentifier
    case invalidRelativePath
    case negativeOrdinal
    case negativeByteCount
    case invalidInverseReference
    case identicalSourceAndDestination
    case invalidAuthorization
}

/// A path relative to one explicit security-scoped root. Absolute paths, empty components,
/// current/parent traversal, and NUL bytes are rejected before persistence.
public struct ScopedRelativePath: Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) throws {
        guard !rawValue.isEmpty,
              !rawValue.hasPrefix("/"),
              !rawValue.contains("\0") else {
            throw LedgerValidationError.invalidRelativePath
        }

        let components = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw LedgerValidationError.invalidRelativePath
        }
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(rawValue: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Identity facts observed through an already-authorized root. Values are opaque and
/// filesystem-specific; no single field is trusted as a universal persistent identifier.
public struct LedgerFileIdentity: Codable, Equatable, Sendable {
    public let volumeID: String
    public let fileID: String
    public let byteCount: Int64
    public let modifiedAt: Date
    public let fingerprint: String

    public init(
        volumeID: String,
        fileID: String,
        byteCount: Int64,
        modifiedAt: Date,
        fingerprint: String
    ) throws {
        guard !volumeID.isEmpty, !fileID.isEmpty, !fingerprint.isEmpty else {
            throw LedgerValidationError.emptyIdentifier
        }
        guard byteCount >= 0 else {
            throw LedgerValidationError.negativeByteCount
        }
        self.volumeID = volumeID
        self.fileID = fileID
        self.byteCount = byteCount
        self.modifiedAt = modifiedAt
        self.fingerprint = fingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case volumeID
        case fileID
        case byteCount
        case modifiedAt
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            volumeID: values.decode(String.self, forKey: .volumeID),
            fileID: values.decode(String.self, forKey: .fileID),
            byteCount: values.decode(Int64.self, forKey: .byteCount),
            modifiedAt: values.decode(Date.self, forKey: .modifiedAt),
            fingerprint: values.decode(String.self, forKey: .fingerprint)
        )
    }
}

public enum LedgerOperationKind: String, Codable, Equatable, Sendable {
    case move
    case undo
}

/// Provenance that authorizes a prepared operation. A model response is intentionally not
/// representable here.
public enum LedgerAuthorization: Codable, Equatable, Sendable {
    case userApproval(planDigest: String, authenticationTag: Data)
    case promotedRule(
        ruleID: String,
        revision: Int,
        intentDigest: String,
        authenticationTag: Data
    )

    public var intentDigest: String {
        switch self {
        case .userApproval(let planDigest, _):
            return planDigest
        case .promotedRule(_, _, let intentDigest, _):
            return intentDigest
        }
    }

    public var authenticationTag: Data {
        switch self {
        case .userApproval(_, let authenticationTag),
             .promotedRule(_, _, _, let authenticationTag):
            return authenticationTag
        }
    }

    var isValid: Bool {
        switch self {
        case .userApproval(let planDigest, let tag):
            return !planDigest.isEmpty && tag.count == 32
        case .promotedRule(let ruleID, let revision, let intentDigest, let tag):
            return !ruleID.isEmpty
                && revision >= 0
                && !intentDigest.isEmpty
                && tag.count == 32
        }
    }
}

public enum LedgerOperationPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case prepared
    case applied
    case committed
    case aborted
    case needsRepair

    public var isTerminal: Bool {
        switch self {
        case .committed, .aborted, .needsRepair:
            return true
        case .prepared, .applied:
            return false
        }
    }
}

/// Immutable operation facts before consent or promoted-rule authorization is attached.
public struct LedgerOperationIntent: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let batchID: String
    public let ordinal: Int
    public let kind: LedgerOperationKind
    public let sourceRootID: String
    public let sourcePath: ScopedRelativePath
    public let destinationRootID: String
    public let destinationPath: ScopedRelativePath
    public let expectedSourceIdentity: LedgerFileIdentity
    public let reversesOperationID: String?

    public init(
        id: String,
        batchID: String,
        ordinal: Int,
        kind: LedgerOperationKind,
        sourceRootID: String,
        sourcePath: ScopedRelativePath,
        destinationRootID: String,
        destinationPath: ScopedRelativePath,
        expectedSourceIdentity: LedgerFileIdentity,
        reversesOperationID: String? = nil
    ) throws {
        guard !id.isEmpty, !batchID.isEmpty, !sourceRootID.isEmpty, !destinationRootID.isEmpty else {
            throw LedgerValidationError.emptyIdentifier
        }
        guard ordinal >= 0 else {
            throw LedgerValidationError.negativeOrdinal
        }
        switch (kind, reversesOperationID) {
        case (.move, nil), (.undo, .some):
            break
        case (.move, .some), (.undo, nil):
            throw LedgerValidationError.invalidInverseReference
        }
        guard sourceRootID != destinationRootID || sourcePath != destinationPath else {
            throw LedgerValidationError.identicalSourceAndDestination
        }
        self.id = id
        self.batchID = batchID
        self.ordinal = ordinal
        self.kind = kind
        self.sourceRootID = sourceRootID
        self.sourcePath = sourcePath
        self.destinationRootID = destinationRootID
        self.destinationPath = destinationPath
        self.expectedSourceIdentity = expectedSourceIdentity
        self.reversesOperationID = reversesOperationID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(String.self, forKey: .id),
            batchID: values.decode(String.self, forKey: .batchID),
            ordinal: values.decode(Int.self, forKey: .ordinal),
            kind: values.decode(LedgerOperationKind.self, forKey: .kind),
            sourceRootID: values.decode(String.self, forKey: .sourceRootID),
            sourcePath: values.decode(ScopedRelativePath.self, forKey: .sourcePath),
            destinationRootID: values.decode(String.self, forKey: .destinationRootID),
            destinationPath: values.decode(ScopedRelativePath.self, forKey: .destinationPath),
            expectedSourceIdentity: values.decode(
                LedgerFileIdentity.self,
                forKey: .expectedSourceIdentity
            ),
            reversesOperationID: values.decodeIfPresent(String.self, forKey: .reversesOperationID)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case batchID
        case ordinal
        case kind
        case sourceRootID
        case sourcePath
        case destinationRootID
        case destinationPath
        case expectedSourceIdentity
        case reversesOperationID
    }
}

/// Authorized operation intent. An undo intent points to the exact committed move it
/// reverses, and authorization must be bound to the canonical digest of the complete batch.
public struct LedgerOperationDraft: Identifiable, Codable, Equatable, Sendable {
    public let intent: LedgerOperationIntent
    public let authorization: LedgerAuthorization

    public var id: String { intent.id }
    public var batchID: String { intent.batchID }
    public var ordinal: Int { intent.ordinal }
    public var kind: LedgerOperationKind { intent.kind }
    public var sourceRootID: String { intent.sourceRootID }
    public var sourcePath: ScopedRelativePath { intent.sourcePath }
    public var destinationRootID: String { intent.destinationRootID }
    public var destinationPath: ScopedRelativePath { intent.destinationPath }
    public var expectedSourceIdentity: LedgerFileIdentity { intent.expectedSourceIdentity }
    public var reversesOperationID: String? { intent.reversesOperationID }

    public init(intent: LedgerOperationIntent, authorization: LedgerAuthorization) throws {
        guard authorization.isValid else {
            throw LedgerValidationError.invalidAuthorization
        }
        self.intent = intent
        self.authorization = authorization
    }

    public init(
        id: String,
        batchID: String,
        ordinal: Int,
        kind: LedgerOperationKind,
        sourceRootID: String,
        sourcePath: ScopedRelativePath,
        destinationRootID: String,
        destinationPath: ScopedRelativePath,
        expectedSourceIdentity: LedgerFileIdentity,
        reversesOperationID: String? = nil,
        authorization: LedgerAuthorization
    ) throws {
        try self.init(
            intent: LedgerOperationIntent(
                id: id,
                batchID: batchID,
                ordinal: ordinal,
                kind: kind,
                sourceRootID: sourceRootID,
                sourcePath: sourcePath,
                destinationRootID: destinationRootID,
                destinationPath: destinationPath,
                expectedSourceIdentity: expectedSourceIdentity,
                reversesOperationID: reversesOperationID
            ),
            authorization: authorization
        )
    }

    private enum CodingKeys: String, CodingKey {
        case intent
        case authorization
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            intent: values.decode(LedgerOperationIntent.self, forKey: .intent),
            authorization: values.decode(LedgerAuthorization.self, forKey: .authorization)
        )
    }
}

public struct LedgerOperation: Identifiable, Codable, Equatable, Sendable {
    public let draft: LedgerOperationDraft
    public let phase: LedgerOperationPhase
    public let observedDestinationIdentity: LedgerFileIdentity?
    public let repairReason: LedgerRepairReason?
    public let createdAt: Date
    public let updatedAt: Date

    public var id: String { draft.id }

    public init(
        draft: LedgerOperationDraft,
        phase: LedgerOperationPhase,
        observedDestinationIdentity: LedgerFileIdentity?,
        repairReason: LedgerRepairReason? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.draft = draft
        self.phase = phase
        self.observedDestinationIdentity = observedDestinationIdentity
        self.repairReason = repairReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum LedgerBatchStatus: String, Codable, Equatable, Sendable {
    case active
    case committed
    case aborted
    case partiallyUndone
    case undone
    case needsRepair
}

public struct LedgerBatch: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let status: LedgerBatchStatus
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, status: LedgerBatchStatus, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct LedgerEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: Int64
    public let operationID: String
    public let phase: LedgerOperationPhase
    public let timestamp: Date
    public let errorDomain: String?
    public let errorCode: Int?

    public init(
        id: Int64,
        operationID: String,
        phase: LedgerOperationPhase,
        timestamp: Date,
        errorDomain: String?,
        errorCode: Int?
    ) {
        self.id = id
        self.operationID = operationID
        self.phase = phase
        self.timestamp = timestamp
        self.errorDomain = errorDomain
        self.errorCode = errorCode
    }
}

public enum FileSystemObservation: Equatable, Sendable {
    case matchingSourceOnly
    case matchingDestinationOnly
    case matchingSourceAndDestination
    case neitherPresent
    case conflictingDestination
    case capabilityUnavailable
}

public enum LedgerRepairReason: String, Codable, Equatable, Sendable {
    case ambiguousPresence
    case missingCommittedItem
    case destinationConflict
    case capabilityUnavailable
    case terminalStateMismatch
}

public enum LedgerRecoveryAction: Equatable, Sendable {
    case retryMutation
    case markApplied
    case markCommitted
    case markAborted
    case holdForRepair(LedgerRepairReason)
    case none
}

/// Pure launch-time reconciliation. It never deletes, overwrites, or infers identity from a
/// path alone; the macOS engine must supply an observation made through authorized roots.
public enum LedgerRecovery {
    public static func action(
        phase: LedgerOperationPhase,
        observation: FileSystemObservation
    ) -> LedgerRecoveryAction {
        if observation == .capabilityUnavailable {
            return .holdForRepair(.capabilityUnavailable)
        }
        if observation == .conflictingDestination {
            return .holdForRepair(.destinationConflict)
        }

        switch (phase, observation) {
        case (_, .capabilityUnavailable):
            return .holdForRepair(.capabilityUnavailable)
        case (_, .conflictingDestination):
            return .holdForRepair(.destinationConflict)
        case (.prepared, .matchingSourceOnly):
            return .retryMutation
        case (.prepared, .matchingDestinationOnly):
            return .markApplied
        case (.applied, .matchingSourceOnly):
            return .retryMutation
        case (.applied, .matchingDestinationOnly):
            return .markCommitted
        case (.committed, .matchingDestinationOnly),
             (.aborted, .matchingSourceOnly),
             (.needsRepair, _):
            return .none
        case (.prepared, .neitherPresent):
            return .holdForRepair(.ambiguousPresence)
        case (.prepared, .matchingSourceAndDestination),
             (.applied, .matchingSourceAndDestination):
            return .holdForRepair(.ambiguousPresence)
        case (.applied, .neitherPresent),
             (.committed, .neitherPresent):
            return .holdForRepair(.missingCommittedItem)
        case (.committed, _), (.aborted, _):
            return .holdForRepair(.terminalStateMismatch)
        }
    }
}

public enum LedgerTransition {
    public static func allows(
        from current: LedgerOperationPhase,
        to next: LedgerOperationPhase
    ) -> Bool {
        switch (current, next) {
        case (.prepared, .applied),
             (.prepared, .aborted),
             (.prepared, .needsRepair),
             (.applied, .committed),
             (.applied, .needsRepair),
             (.committed, .needsRepair),
             (.aborted, .needsRepair):
            return true
        default:
            return false
        }
    }
}
