import Foundation
import TydlyCore
import TydlyPersistence

public actor RootCapabilityStore {
    private let ledger: EncryptedOperationLedger
    private let bookmarkCodec: any SecurityScopedBookmarkCoding
    private let inspector: any RootResourceInspecting
    private let scopeAccessor: any SecurityScopeAccessing
    private let trustedRoots: any TrustedRootLocating
    private let makeUUID: @Sendable () -> UUID
    private var operationInProgress = false

    public init(
        ledger: EncryptedOperationLedger,
        bookmarkCodec: any SecurityScopedBookmarkCoding = FoundationBookmarkCodec(),
        inspector: any RootResourceInspecting = FoundationRootInspector(),
        scopeAccessor: any SecurityScopeAccessing = FoundationSecurityScopeAccessor(),
        trustedRoots: any TrustedRootLocating = FoundationTrustedRootLocator(),
        makeUUID: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.ledger = ledger
        self.bookmarkCodec = bookmarkCodec
        self.inspector = inspector
        self.scopeAccessor = scopeAccessor
        self.trustedRoots = trustedRoots
        self.makeUUID = makeUUID
    }

    public func registerPanelSelection(
        logicalRootID: String,
        purpose: RootPurpose,
        selectedURL: URL
    ) async throws -> RootGenerationDescriptor {
        try await registerPanelSelections(
            [
                RootPanelSelection(
                    logicalRootID: logicalRootID,
                    purpose: purpose,
                    url: selectedURL
                )
            ]
        )[0]
    }

    /// Validates every Powerbox selection as one set, then commits all bookmark generations
    /// and binding changes in one SQL transaction. Cancellation before this call stores none.
    public func registerPanelSelections(
        _ selections: [RootPanelSelection]
    ) async throws -> [RootGenerationDescriptor] {
        defer {
            // NSOpenPanel implicitly starts each selected URL.
            for selection in selections {
                scopeAccessor.stopAccessing(selection.url)
            }
        }
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }
        let processLock = try await acquireProcessLock()
        defer { processLock.close() }

        guard !selections.isEmpty,
              Set(selections.map(\.logicalRootID)).count == selections.count else {
            throw RootCapabilityError.duplicateSelection
        }

        try Task.checkCancellation()
        let rootSetSnapshot = try await ledger.rootBindingSnapshot()
        let replacingLogicalIDs = Set(selections.map(\.logicalRootID))
        let existing = try await existingRootsForValidation(
            bindings: rootSetSnapshot.bindings,
            excluding: replacingLogicalIDs
        )
        defer { existing.forEach { scopeAccessor.stopAccessing($0.url) } }

        var inspections: [URL: RootInspection] = [:]
        for selection in selections {
            try Task.checkCancellation()
            inspections[selection.url] = try await inspector.inspect(selection.url)
        }

        for selection in selections {
            try Task.checkCancellation()
            guard let inspection = inspections[selection.url] else {
                throw RootCapabilityError.bindingUnavailable
            }
            let otherSelectedURLs = selections
                .filter { $0.logicalRootID != selection.logicalRootID }
                .map(\.url)
            let context = try policyContext(
                selectedURL: selection.url,
                purpose: selection.purpose,
                otherRootURLs: existing.map(\.url) + otherSelectedURLs
            )
            try RootSelectionPolicy.validate(
                inspection: inspection,
                purpose: selection.purpose,
                context: context
            )
        }

        var registrations: [RootGenerationRegistration] = []
        for selection in selections {
            try Task.checkCancellation()
            guard let inspection = inspections[selection.url] else {
                throw RootCapabilityError.bindingUnavailable
            }
            let bookmark: Data
            do {
                bookmark = try bookmarkCodec.createBookmark(for: selection.url)
            } catch {
                throw RootCapabilityError.bookmarkCreationFailed
            }
            let generations = try await ledger.rootGenerations(
                logicalRootID: selection.logicalRootID
            )
            let generation = (generations.last?.descriptor.generation ?? -1) + 1
            let descriptor = try RootGenerationDescriptor(
                id: makeUUID().uuidString,
                logicalRootID: selection.logicalRootID,
                generation: generation,
                purpose: selection.purpose,
                displayName: inspection.displayName,
                identity: inspection.identity
            )
            registrations.append(
                RootGenerationRegistration(
                    descriptor: descriptor,
                    bookmark: bookmark,
                    status: .active
                )
            )
        }

        try Task.checkCancellation()
        try await ledger.registerRootGenerations(
            registrations,
            expectedRootSetRevision: rootSetSnapshot.revision,
            replacingLegacyBindings: rootSetSnapshot.bindings.contains {
                $0.purpose == .legacy
            }
        )
        return registrations.map(\.descriptor)
    }

    /// Keeps the security scope and the store's exclusive capability operation alive for the
    /// complete closure, then always relinquishes access before returning or throwing.
    public func withResolvedRoot<T: Sendable>(
        logicalRootID: String,
        _ operation: @Sendable (URL, RootGenerationDescriptor) async throws -> T
    ) async throws -> T {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }
        let processLock = try await acquireProcessLock()
        defer { processLock.close() }
        let lease = try await resolveLease(
            logicalRootID: logicalRootID,
            expectedRootGenerationID: nil
        )
        defer { lease.close() }
        return try await operation(lease.url, lease.descriptor)
    }

    /// Mutation plans use immutable generation IDs. If bookmark refresh changes the active
    /// generation, this method fails so the plan must be rebuilt and approved again.
    public func withResolvedRootGeneration<T: Sendable>(
        rootGenerationID: String,
        _ operation: @Sendable (URL, RootGenerationDescriptor) async throws -> T
    ) async throws -> T {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }
        let processLock = try await acquireProcessLock()
        defer { processLock.close() }
        guard let root = try await ledger.root(id: rootGenerationID) else {
            throw RootCapabilityError.bindingUnavailable
        }
        let lease = try await resolveLease(
            logicalRootID: root.descriptor.logicalRootID,
            expectedRootGenerationID: rootGenerationID
        )
        defer { lease.close() }
        return try await operation(lease.url, lease.descriptor)
    }

    /// Recovery may need the exact generation recorded by a durable prepared operation even
    /// after a stale refresh activated a successor. It validates identity and current policy
    /// but never retargets the operation or changes the active binding.
    public func withRecordedRootGenerationForRecovery<T: Sendable>(
        operationID: String,
        rootGenerationID: String,
        _ operation: @Sendable (URL, RootGenerationDescriptor) async throws -> T
    ) async throws -> T {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }
        let processLock = try await acquireProcessLock()
        defer { processLock.close() }
        let reservation = try await ledger.reserveRecoveryOperation(
            operationID: operationID,
            rootGenerationID: rootGenerationID
        )
        guard let root = try await ledger.root(id: rootGenerationID) else {
            try? await ledger.releaseRecoveryOperation(reservation)
            throw RootCapabilityError.bindingUnavailable
        }
        do {
            let lease = try await resolveRecordedLease(root)
            defer { lease.close() }
            let result = try await operation(lease.url, lease.descriptor)
            try await ledger.releaseRecoveryOperation(reservation)
            return result
        } catch {
            try? await ledger.releaseRecoveryOperation(reservation)
            throw error
        }
    }

    public func hasActiveBindings(_ logicalRootIDs: Set<String>) async throws -> Bool {
        let bindings = try await ledger.rootBindings()
        let active = Set(
            bindings
                .filter { $0.status == .active }
                .map(\.id)
        )
        return logicalRootIDs.isSubset(of: active)
    }

    public func markNeedsReauthorization(
        _ logicalRootID: String,
        expectedActiveRootID: String
    ) async throws {
        try beginExclusiveOperation()
        defer { endExclusiveOperation() }
        let processLock = try await acquireProcessLock()
        defer { processLock.close() }
        try await markNeedsReauthorizationWithoutLock(
            logicalRootID,
            expectedActiveRootID: expectedActiveRootID
        )
    }

    private func resolveLease(
        logicalRootID: String,
        expectedRootGenerationID: String?
    ) async throws -> SecurityScopedRootLease {
        let rootSetSnapshot = try await ledger.rootBindingSnapshot()
        guard let binding = rootSetSnapshot.bindings.first(where: { $0.id == logicalRootID }),
              let root = try await ledger.activeRoot(logicalRootID: logicalRootID),
              root.id == binding.activeRootID else {
            throw RootCapabilityError.bindingUnavailable
        }
        guard binding.status == .active else {
            throw RootCapabilityError.needsReauthorization
        }
        if let expectedRootGenerationID, root.id != expectedRootGenerationID {
            throw RootCapabilityError.generationChanged
        }

        let resolution: BookmarkResolution
        do {
            resolution = try bookmarkCodec.resolveBookmark(root.bookmark)
        } catch {
            try? await markNeedsReauthorizationWithoutLock(
                logicalRootID,
                expectedActiveRootID: root.id
            )
            throw RootCapabilityError.bookmarkResolutionFailed
        }
        guard scopeAccessor.startAccessing(resolution.url) else {
            try? await markNeedsReauthorizationWithoutLock(
                logicalRootID,
                expectedActiveRootID: root.id
            )
            throw RootCapabilityError.accessDenied
        }

        let existing: [ExistingValidationRoot]
        do {
            existing = try await existingRootsForValidation(
                bindings: rootSetSnapshot.bindings,
                excluding: [logicalRootID]
            )
        } catch {
            scopeAccessor.stopAccessing(resolution.url)
            throw error
        }
        defer { existing.forEach { scopeAccessor.stopAccessing($0.url) } }

        var descriptor = root.descriptor
        do {
            let inspection = try await inspector.inspect(resolution.url)
            let context = try policyContext(
                selectedURL: resolution.url,
                purpose: descriptor.purpose,
                otherRootURLs: existing.map(\.url)
            )
            try RootSelectionPolicy.validate(
                inspection: inspection,
                purpose: descriptor.purpose,
                context: context
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
                try await ledger.registerRootGenerations(
                    [
                        RootGenerationRegistration(
                            descriptor: descriptor,
                            bookmark: refreshedBookmark,
                            status: .active
                        )
                    ],
                    expectedRootSetRevision: rootSetSnapshot.revision
                )
                if expectedRootGenerationID != nil {
                    throw RootCapabilityError.generationChanged
                }
            }
        } catch {
            scopeAccessor.stopAccessing(resolution.url)
            try? await markNeedsReauthorizationWithoutLock(
                logicalRootID,
                expectedActiveRootID: root.id
            )
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

    private func resolveRecordedLease(
        _ root: LedgerRootRecord
    ) async throws -> SecurityScopedRootLease {
        let resolution: BookmarkResolution
        do {
            resolution = try bookmarkCodec.resolveBookmark(root.bookmark)
        } catch {
            throw RootCapabilityError.bookmarkResolutionFailed
        }
        guard scopeAccessor.startAccessing(resolution.url) else {
            throw RootCapabilityError.accessDenied
        }

        do {
            let snapshot = try await ledger.rootBindingSnapshot()
            let existing = try await existingRootsForValidation(
                bindings: snapshot.bindings,
                excluding: [root.descriptor.logicalRootID]
            )
            defer { existing.forEach { scopeAccessor.stopAccessing($0.url) } }
            let inspection = try await inspector.inspect(resolution.url)
            let context = try policyContext(
                selectedURL: resolution.url,
                purpose: root.descriptor.purpose,
                otherRootURLs: existing.map(\.url)
            )
            try RootSelectionPolicy.validate(
                inspection: inspection,
                purpose: root.descriptor.purpose,
                context: context
            )
            guard inspection.identity == root.descriptor.identity else {
                throw RootCapabilityError.identityChanged
            }
        } catch {
            scopeAccessor.stopAccessing(resolution.url)
            if let capabilityError = error as? RootCapabilityError {
                throw capabilityError
            }
            throw RootCapabilityError.bookmarkResolutionFailed
        }

        return SecurityScopedRootLease(
            url: resolution.url,
            descriptor: root.descriptor,
            accessor: scopeAccessor
        )
    }

    private func existingRootsForValidation(
        bindings: [RootBindingRecord],
        excluding logicalRootIDs: Set<String>
    ) async throws -> [ExistingValidationRoot] {
        var result: [ExistingValidationRoot] = []
        do {
            for binding in bindings where !logicalRootIDs.contains(binding.id) {
                if binding.purpose == .legacy {
                    continue
                }
                guard binding.status == .active,
                      let root = try await ledger.activeRoot(logicalRootID: binding.id),
                      root.id == binding.activeRootID else {
                    throw RootCapabilityError.existingRootUnavailable
                }
                let resolution: BookmarkResolution
                do {
                    resolution = try bookmarkCodec.resolveBookmark(root.bookmark)
                } catch {
                    try? await markNeedsReauthorizationWithoutLock(
                        binding.id,
                        expectedActiveRootID: root.id
                    )
                    throw RootCapabilityError.existingRootUnavailable
                }
                guard scopeAccessor.startAccessing(resolution.url) else {
                    try? await markNeedsReauthorizationWithoutLock(
                        binding.id,
                        expectedActiveRootID: root.id
                    )
                    throw RootCapabilityError.existingRootUnavailable
                }
                do {
                    let inspection = try await inspector.inspect(resolution.url)
                    let context = try policyContext(
                        selectedURL: resolution.url,
                        purpose: root.descriptor.purpose,
                        otherRootURLs: []
                    )
                    try RootSelectionPolicy.validate(
                        inspection: inspection,
                        purpose: root.descriptor.purpose,
                        context: context
                    )
                    guard inspection.identity == root.descriptor.identity else {
                        throw RootCapabilityError.identityChanged
                    }
                } catch {
                    scopeAccessor.stopAccessing(resolution.url)
                    try? await markNeedsReauthorizationWithoutLock(
                        binding.id,
                        expectedActiveRootID: root.id
                    )
                    throw RootCapabilityError.existingRootUnavailable
                }
                result.append(
                    ExistingValidationRoot(
                        url: resolution.url,
                        descriptor: root.descriptor
                    )
                )
            }
            return result
        } catch {
            result.forEach { scopeAccessor.stopAccessing($0.url) }
            throw error
        }
    }

    private func policyContext(
        selectedURL: URL,
        purpose: RootPurpose,
        otherRootURLs: [URL]
    ) throws -> RootPolicyContext {
        let matchesRequiredFolder: Bool
        if purpose == .sourceDesktop || purpose == .sourceDownloads {
            guard let requiredURL = trustedRoots.requiredURL(for: purpose) else {
                throw RootCapabilityError.wrongRequiredFolder
            }
            matchesRequiredFolder = try inspector.relationship(
                of: requiredURL,
                to: selectedURL
            ) == .same
        } else {
            matchesRequiredFolder = true
        }

        var isBroadRoot = false
        for forbidden in trustedRoots.forbiddenBroadRoots {
            let forbiddenContainsSelection = try inspector.relationship(
                of: forbidden,
                to: selectedURL
            )
            let selectionContainsForbidden = try inspector.relationship(
                of: selectedURL,
                to: forbidden
            )
            if forbiddenContainsSelection == .same
                || selectionContainsForbidden == .same
                || selectionContainsForbidden == .contains {
                isBroadRoot = true
                break
            }
        }

        var overlapsExistingRoot = false
        for otherURL in otherRootURLs {
            let existingContainsSelected = try inspector.relationship(
                of: otherURL,
                to: selectedURL
            )
            let selectedContainsExisting = try inspector.relationship(
                of: selectedURL,
                to: otherURL
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
            isHomeOrFilesystemRoot: isBroadRoot,
            overlapsExistingRoot: overlapsExistingRoot
        )
    }

    private func markNeedsReauthorizationWithoutLock(
        _ logicalRootID: String,
        expectedActiveRootID: String
    ) async throws {
        try await ledger.updateRootBindingStatus(
            logicalRootID: logicalRootID,
            expectedActiveRootID: expectedActiveRootID,
            status: .needsReauthorization
        )
    }

    private func beginExclusiveOperation() throws {
        guard !operationInProgress else {
            throw RootCapabilityError.operationInProgress
        }
        operationInProgress = true
    }

    private func endExclusiveOperation() {
        operationInProgress = false
    }

    private func acquireProcessLock() async throws -> RootCapabilityProcessLock {
        do {
            return try await ledger.acquireRootCapabilityProcessLock()
        } catch LedgerStoreError.rootCapabilityBusy {
            throw RootCapabilityError.operationInProgress
        }
    }
}

private struct ExistingValidationRoot {
    let url: URL
    let descriptor: RootGenerationDescriptor
}
