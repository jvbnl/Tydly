import Foundation
import TydlyCore
import TydlyPersistence

public actor RootCapabilityStore {
    private let ledger: EncryptedOperationLedger
    private let bookmarkCodec: any SecurityScopedBookmarkCoding
    private let inspector: any RootResourceInspecting
    private let scopeAccessor: any SecurityScopeAccessing
    private let makeUUID: @Sendable () -> UUID

    public init(
        ledger: EncryptedOperationLedger,
        bookmarkCodec: any SecurityScopedBookmarkCoding = FoundationBookmarkCodec(),
        inspector: any RootResourceInspecting = FoundationRootInspector(),
        scopeAccessor: any SecurityScopeAccessing = FoundationSecurityScopeAccessor(),
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.ledger = ledger
        self.bookmarkCodec = bookmarkCodec
        self.inspector = inspector
        self.scopeAccessor = scopeAccessor
        self.makeUUID = makeUUID
    }

    /// Persists a URL returned directly by NSOpenPanel. Powerbox starts implicit access for
    /// that URL, so this method always relinquishes it before returning.
    public func registerPanelSelection(
        logicalRootID: String,
        purpose: RootPurpose,
        selectedURL: URL,
        requiredURL: URL? = nil
    ) async throws -> RootGenerationDescriptor {
        defer { selectedURL.stopAccessingSecurityScopedResource() }

        let inspection = try await inspector.inspect(selectedURL)
        let context = try await policyContext(
            selectedURL: selectedURL,
            logicalRootID: logicalRootID,
            purpose: purpose,
            requiredURL: requiredURL
        )
        try RootSelectionPolicy.validate(
            inspection: inspection,
            purpose: purpose,
            context: context
        )

        if let binding = try await ledger.rootBinding(logicalRootID: logicalRootID),
           let active = try await ledger.activeRoot(logicalRootID: logicalRootID),
           binding.status == .active,
           active.descriptor.purpose == purpose,
           active.descriptor.identity == inspection.identity {
            return active.descriptor
        }

        let bookmark: Data
        do {
            bookmark = try bookmarkCodec.createBookmark(for: selectedURL)
        } catch {
            throw RootCapabilityError.bookmarkCreationFailed
        }

        let generations = try await ledger.rootGenerations(logicalRootID: logicalRootID)
        let generation = (generations.last?.descriptor.generation ?? -1) + 1
        let descriptor = try RootGenerationDescriptor(
            id: makeUUID().uuidString,
            logicalRootID: logicalRootID,
            generation: generation,
            purpose: purpose,
            displayName: inspection.displayName,
            identity: inspection.identity
        )
        try await ledger.registerRootGeneration(
            descriptor,
            bookmark: bookmark,
            status: .active
        )
        return descriptor
    }

    /// Resolves the active bookmark without UI or mounting. Failures mark the logical root
    /// for explicit reauthorization; there is never an absolute-path fallback.
    public func resolve(logicalRootID: String) async throws -> SecurityScopedRootLease {
        guard let binding = try await ledger.rootBinding(logicalRootID: logicalRootID),
              let root = try await ledger.activeRoot(logicalRootID: logicalRootID) else {
            throw RootCapabilityError.bindingUnavailable
        }
        guard binding.status == .active else {
            throw RootCapabilityError.needsReauthorization
        }

        let resolution: BookmarkResolution
        do {
            resolution = try bookmarkCodec.resolveBookmark(root.bookmark)
        } catch {
            try? await markNeedsReauthorization(logicalRootID)
            throw RootCapabilityError.bookmarkResolutionFailed
        }
        guard scopeAccessor.startAccessing(resolution.url) else {
            try? await markNeedsReauthorization(logicalRootID)
            throw RootCapabilityError.accessDenied
        }

        var descriptor = root.descriptor
        do {
            let inspection = try await inspector.inspect(resolution.url)
            try RootSelectionPolicy.validate(
                inspection: inspection,
                purpose: descriptor.purpose,
                context: RootPolicyContext(
                    matchesRequiredFolder: true,
                    isHomeOrFilesystemRoot: false,
                    overlapsExistingRoot: false
                )
            )
            guard inspection.identity == descriptor.identity else {
                throw RootCapabilityError.identityChanged
            }

            if resolution.isStale {
                let refreshedBookmark = try bookmarkCodec.createBookmark(for: resolution.url)
                descriptor = try RootGenerationDescriptor(
                    id: makeUUID().uuidString,
                    logicalRootID: descriptor.logicalRootID,
                    generation: descriptor.generation + 1,
                    purpose: descriptor.purpose,
                    displayName: inspection.displayName,
                    identity: inspection.identity
                )
                try await ledger.registerRootGeneration(
                    descriptor,
                    bookmark: refreshedBookmark,
                    status: .active
                )
            }
        } catch {
            scopeAccessor.stopAccessing(resolution.url)
            try? await markNeedsReauthorization(logicalRootID)
            if let capabilityError = error as? RootCapabilityError {
                throw capabilityError
            }
            throw RootCapabilityError.bookmarkResolutionFailed
        }

        return SecurityScopedRootLease(
            url: resolution.url,
            descriptor: descriptor,
            accessor: scopeAccessor
        )
    }

    public func markNeedsReauthorization(_ logicalRootID: String) async throws {
        try await ledger.updateRootBindingStatus(
            logicalRootID: logicalRootID,
            status: .needsReauthorization
        )
    }

    private func policyContext(
        selectedURL: URL,
        logicalRootID: String,
        purpose: RootPurpose,
        requiredURL: URL?
    ) async throws -> RootPolicyContext {
        let matchesRequiredFolder: Bool
        if purpose == .sourceDesktop || purpose == .sourceDownloads {
            guard let requiredURL else {
                throw RootCapabilityError.wrongRequiredFolder
            }
            matchesRequiredFolder = try inspector.relationship(
                of: requiredURL,
                to: selectedURL
            ) == .same
        } else {
            matchesRequiredFolder = true
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let filesystemRoot = URL(fileURLWithPath: "/", isDirectory: true)
        let isHomeOrFilesystemRoot = try inspector.relationship(
            of: home,
            to: selectedURL
        ) == .same || inspector.relationship(
            of: filesystemRoot,
            to: selectedURL
        ) == .same

        var overlapsExistingRoot = false
        for binding in try await ledger.rootBindings() where binding.id != logicalRootID {
            guard binding.status == .active else {
                throw RootCapabilityError.existingRootUnavailable
            }
            guard let existing = try await ledger.activeRoot(logicalRootID: binding.id) else {
                throw RootCapabilityError.existingRootUnavailable
            }
            let resolution: BookmarkResolution
            do {
                resolution = try bookmarkCodec.resolveBookmark(existing.bookmark)
            } catch {
                try? await markNeedsReauthorization(binding.id)
                throw RootCapabilityError.existingRootUnavailable
            }
            guard scopeAccessor.startAccessing(resolution.url) else {
                try? await markNeedsReauthorization(binding.id)
                throw RootCapabilityError.existingRootUnavailable
            }
            defer { scopeAccessor.stopAccessing(resolution.url) }

            let existingContainsSelected = try inspector.relationship(
                of: resolution.url,
                to: selectedURL
            )
            let selectedContainsExisting = try inspector.relationship(
                of: selectedURL,
                to: resolution.url
            )
            if existingContainsSelected == .same
                || existingContainsSelected == .contains
                || selectedContainsExisting == .same
                || selectedContainsExisting == .contains {
                overlapsExistingRoot = true
                break
            }
        }

        return RootPolicyContext(
            matchesRequiredFolder: matchesRequiredFolder,
            isHomeOrFilesystemRoot: isHomeOrFilesystemRoot,
            overlapsExistingRoot: overlapsExistingRoot
        )
    }
}
