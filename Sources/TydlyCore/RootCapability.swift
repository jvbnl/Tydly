import Foundation

public enum RootPurpose: String, Codable, CaseIterable, Equatable, Sendable {
    case sourceDesktop
    case sourceDownloads
    case destination
    case legacy
}

public enum RootBindingStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case active
    case needsReauthorization
    case unsupported
}

public enum RootCapabilityValidationError: Error, Equatable, Sendable {
    case emptyIdentifier
    case negativeGeneration
}

/// Filesystem identity captured while the selected root is actively authorized. Paths are
/// deliberately absent; the encrypted bookmark is the persistent capability.
public struct RootResourceIdentity: Codable, Equatable, Sendable {
    public let volumeID: String
    public let fileID: String

    public init(volumeID: String, fileID: String) throws {
        guard !volumeID.isEmpty, !fileID.isEmpty else {
            throw RootCapabilityValidationError.emptyIdentifier
        }
        self.volumeID = volumeID
        self.fileID = fileID
    }

    private enum CodingKeys: String, CodingKey {
        case volumeID
        case fileID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            volumeID: values.decode(String.self, forKey: .volumeID),
            fileID: values.decode(String.self, forKey: .fileID)
        )
    }
}

/// Immutable metadata for one bookmark generation. Refreshing a stale bookmark creates a
/// new generation and atomically repoints the logical binding; history never retargets.
public struct RootGenerationDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let logicalRootID: String
    public let generation: Int
    public let purpose: RootPurpose
    public let displayName: String
    public let identity: RootResourceIdentity

    public init(
        id: String,
        logicalRootID: String,
        generation: Int,
        purpose: RootPurpose,
        displayName: String,
        identity: RootResourceIdentity
    ) throws {
        guard !id.isEmpty, !logicalRootID.isEmpty, !displayName.isEmpty else {
            throw RootCapabilityValidationError.emptyIdentifier
        }
        guard generation >= 0 else {
            throw RootCapabilityValidationError.negativeGeneration
        }
        self.id = id
        self.logicalRootID = logicalRootID
        self.generation = generation
        self.purpose = purpose
        self.displayName = displayName
        self.identity = identity
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case logicalRootID
        case generation
        case purpose
        case displayName
        case identity
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(String.self, forKey: .id),
            logicalRootID: values.decode(String.self, forKey: .logicalRootID),
            generation: values.decode(Int.self, forKey: .generation),
            purpose: values.decode(RootPurpose.self, forKey: .purpose),
            displayName: values.decode(String.self, forKey: .displayName),
            identity: values.decode(RootResourceIdentity.self, forKey: .identity)
        )
    }
}
