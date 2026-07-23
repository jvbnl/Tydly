import Foundation
import TydlyCore

public enum RootCapabilityError: Error, Equatable, Sendable {
    case selectionCancelled
    case notDirectory
    case symbolicLink
    case packageDirectory
    case nonLocalVolume
    case readOnlyVolume
    case providerBacked
    case broadRoot
    case wrongRequiredFolder
    case overlapsExistingRoot
    case existingRootUnavailable
    case bookmarkCreationFailed
    case bookmarkResolutionFailed
    case accessDenied
    case identityChanged
    case bindingUnavailable
    case needsReauthorization
}

public struct RootInspection: Equatable, Sendable {
    public let displayName: String
    public let identity: RootResourceIdentity
    public let isDirectory: Bool
    public let isSymbolicLink: Bool
    public let isPackage: Bool
    public let isLocalVolume: Bool
    public let isReadOnlyVolume: Bool
    public let isProviderBacked: Bool

    public init(
        displayName: String,
        identity: RootResourceIdentity,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        isPackage: Bool,
        isLocalVolume: Bool,
        isReadOnlyVolume: Bool,
        isProviderBacked: Bool
    ) {
        self.displayName = displayName
        self.identity = identity
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.isPackage = isPackage
        self.isLocalVolume = isLocalVolume
        self.isReadOnlyVolume = isReadOnlyVolume
        self.isProviderBacked = isProviderBacked
    }
}

public struct BookmarkResolution: Sendable {
    public let url: URL
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public protocol SecurityScopedBookmarkCoding: Sendable {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ bookmark: Data) throws -> BookmarkResolution
}

public protocol RootResourceInspecting: Sendable {
    func inspect(_ url: URL) async throws -> RootInspection
    func relationship(
        of directory: URL,
        to item: URL
    ) throws -> FileManager.URLRelationship
}

public protocol SecurityScopeAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct RootPolicyContext: Equatable, Sendable {
    public let matchesRequiredFolder: Bool
    public let isHomeOrFilesystemRoot: Bool
    public let overlapsExistingRoot: Bool

    public init(
        matchesRequiredFolder: Bool,
        isHomeOrFilesystemRoot: Bool,
        overlapsExistingRoot: Bool
    ) {
        self.matchesRequiredFolder = matchesRequiredFolder
        self.isHomeOrFilesystemRoot = isHomeOrFilesystemRoot
        self.overlapsExistingRoot = overlapsExistingRoot
    }
}

public enum RootSelectionPolicy {
    public static func validate(
        inspection: RootInspection,
        purpose: RootPurpose,
        context: RootPolicyContext
    ) throws {
        guard inspection.isDirectory else { throw RootCapabilityError.notDirectory }
        guard !inspection.isSymbolicLink else { throw RootCapabilityError.symbolicLink }
        guard !inspection.isPackage else { throw RootCapabilityError.packageDirectory }
        guard inspection.isLocalVolume else { throw RootCapabilityError.nonLocalVolume }
        guard !inspection.isReadOnlyVolume else { throw RootCapabilityError.readOnlyVolume }
        guard !inspection.isProviderBacked else { throw RootCapabilityError.providerBacked }
        guard !context.isHomeOrFilesystemRoot else { throw RootCapabilityError.broadRoot }
        if purpose == .sourceDesktop || purpose == .sourceDownloads {
            guard context.matchesRequiredFolder else {
                throw RootCapabilityError.wrongRequiredFolder
            }
        }
        guard !context.overlapsExistingRoot else {
            throw RootCapabilityError.overlapsExistingRoot
        }
    }
}

public final class SecurityScopedRootLease: @unchecked Sendable {
    public let url: URL
    public let descriptor: RootGenerationDescriptor

    private let accessor: any SecurityScopeAccessing
    private let lock = NSLock()
    private var isActive = true

    init(
        url: URL,
        descriptor: RootGenerationDescriptor,
        accessor: any SecurityScopeAccessing
    ) {
        self.url = url
        self.descriptor = descriptor
        self.accessor = accessor
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { return }
        isActive = false
        accessor.stopAccessing(url)
    }

    deinit {
        close()
    }
}
