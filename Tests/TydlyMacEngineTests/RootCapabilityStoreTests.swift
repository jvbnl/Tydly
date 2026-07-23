import Foundation
import XCTest
import TydlyCore
@testable import TydlyMacEngine
import TydlyPersistence

final class RootCapabilityStoreTests: XCTestCase {
    func testPolicyFailsClosedForUnsupportedRoots() throws {
        let identity = try RootResourceIdentity(volumeID: "volume", fileID: "file")
        let safe = RootInspection(
            displayName: "Root",
            identity: identity,
            isDirectory: true,
            isSymbolicLink: false,
            isPackage: false,
            isLocalVolume: true,
            isReadOnlyVolume: false,
            isProviderBacked: false
        )
        let safeContext = RootPolicyContext(
            matchesRequiredFolder: true,
            isHomeOrFilesystemRoot: false,
            overlapsExistingRoot: false
        )

        XCTAssertNoThrow(
            try RootSelectionPolicy.validate(
                inspection: safe,
                purpose: .sourceDesktop,
                context: safeContext
            )
        )

        let rejected: [(RootInspection, RootPolicyContext, RootCapabilityError)] = [
            (
                replacing(safe, isDirectory: false),
                safeContext,
                .notDirectory
            ),
            (
                replacing(safe, isSymbolicLink: true),
                safeContext,
                .symbolicLink
            ),
            (
                replacing(safe, isPackage: true),
                safeContext,
                .packageDirectory
            ),
            (
                replacing(safe, isLocalVolume: false),
                safeContext,
                .nonLocalVolume
            ),
            (
                replacing(safe, isReadOnlyVolume: true),
                safeContext,
                .readOnlyVolume
            ),
            (
                replacing(safe, isProviderBacked: true),
                safeContext,
                .providerBacked
            ),
            (
                safe,
                RootPolicyContext(
                    matchesRequiredFolder: true,
                    isHomeOrFilesystemRoot: true,
                    overlapsExistingRoot: false
                ),
                .broadRoot
            ),
            (
                safe,
                RootPolicyContext(
                    matchesRequiredFolder: false,
                    isHomeOrFilesystemRoot: false,
                    overlapsExistingRoot: false
                ),
                .wrongRequiredFolder
            ),
            (
                safe,
                RootPolicyContext(
                    matchesRequiredFolder: true,
                    isHomeOrFilesystemRoot: false,
                    overlapsExistingRoot: true
                ),
                .overlapsExistingRoot
            )
        ]

        for (inspection, context, expected) in rejected {
            XCTAssertThrowsError(
                try RootSelectionPolicy.validate(
                    inspection: inspection,
                    purpose: .sourceDesktop,
                    context: context
                )
            ) {
                XCTAssertEqual($0 as? RootCapabilityError, expected)
            }
        }
    }

    func testPanelSelectionPersistsEncryptedGenerationAndBinding() async throws {
        let fixture = try CapabilityFixture()
        defer { fixture.remove() }

        let descriptor = try await fixture.store.registerPanelSelection(
            logicalRootID: "source.desktop",
            purpose: .sourceDesktop,
            selectedURL: fixture.desktop,
            requiredURL: fixture.desktop
        )
        let binding = try await fixture.ledger.rootBinding(logicalRootID: "source.desktop")
        let active = try await fixture.ledger.activeRoot(logicalRootID: "source.desktop")

        XCTAssertEqual(descriptor.generation, 0)
        XCTAssertEqual(binding?.activeRootID, descriptor.id)
        XCTAssertEqual(binding?.status, .active)
        XCTAssertEqual(active?.descriptor, descriptor)
        XCTAssertFalse(active?.bookmark.isEmpty ?? true)
        try await fixture.ledger.close()
    }

    func testStaleBookmarkRefreshesOnlyAfterIdentityMatches() async throws {
        let fixture = try CapabilityFixture()
        defer { fixture.remove() }

        let first = try await fixture.store.registerPanelSelection(
            logicalRootID: "source.desktop",
            purpose: .sourceDesktop,
            selectedURL: fixture.desktop,
            requiredURL: fixture.desktop
        )
        fixture.bookmarks.markLatestStale(for: fixture.desktop)

        let lease = try await fixture.store.resolve(logicalRootID: "source.desktop")
        XCTAssertEqual(lease.descriptor.generation, 1)
        XCTAssertEqual(lease.descriptor.identity, first.identity)
        lease.close()
        lease.close()

        let generations = try await fixture.ledger.rootGenerations(
            logicalRootID: "source.desktop"
        )
        XCTAssertEqual(generations.map(\.descriptor.generation), [0, 1])
        XCTAssertEqual(fixture.scopes.startCount, 1)
        XCTAssertEqual(fixture.scopes.stopCount, 1)
        try await fixture.ledger.close()
    }

    func testChangedIdentityRequiresExplicitReauthorization() async throws {
        let fixture = try CapabilityFixture()
        defer { fixture.remove() }

        _ = try await fixture.store.registerPanelSelection(
            logicalRootID: "source.desktop",
            purpose: .sourceDesktop,
            selectedURL: fixture.desktop,
            requiredURL: fixture.desktop
        )
        fixture.inspector.setInspection(
            for: fixture.desktop,
            identity: try RootResourceIdentity(volumeID: "volume", fileID: "replacement")
        )

        do {
            _ = try await fixture.store.resolve(logicalRootID: "source.desktop")
            XCTFail("changed root identity must never silently retarget history")
        } catch {
            XCTAssertEqual(error as? RootCapabilityError, .identityChanged)
        }
        let binding = try await fixture.ledger.rootBinding(logicalRootID: "source.desktop")
        XCTAssertEqual(binding?.status, .needsReauthorization)
        XCTAssertEqual(fixture.scopes.startCount, fixture.scopes.stopCount)
        try await fixture.ledger.close()
    }

    func testOverlappingSelectionIsRejected() async throws {
        let fixture = try CapabilityFixture()
        defer { fixture.remove() }

        _ = try await fixture.store.registerPanelSelection(
            logicalRootID: "source.desktop",
            purpose: .sourceDesktop,
            selectedURL: fixture.desktop,
            requiredURL: fixture.desktop
        )
        let nested = fixture.desktop.appendingPathComponent("Nested", isDirectory: true)
        fixture.inspector.setInspection(
            for: nested,
            identity: try RootResourceIdentity(volumeID: "volume", fileID: "nested")
        )

        do {
            _ = try await fixture.store.registerPanelSelection(
                logicalRootID: "destination.nested",
                purpose: .destination,
                selectedURL: nested
            )
            XCTFail("overlapping roots must be rejected")
        } catch {
            XCTAssertEqual(error as? RootCapabilityError, .overlapsExistingRoot)
        }
        try await fixture.ledger.close()
    }

    private func replacing(
        _ value: RootInspection,
        isDirectory: Bool? = nil,
        isSymbolicLink: Bool? = nil,
        isPackage: Bool? = nil,
        isLocalVolume: Bool? = nil,
        isReadOnlyVolume: Bool? = nil,
        isProviderBacked: Bool? = nil
    ) -> RootInspection {
        RootInspection(
            displayName: value.displayName,
            identity: value.identity,
            isDirectory: isDirectory ?? value.isDirectory,
            isSymbolicLink: isSymbolicLink ?? value.isSymbolicLink,
            isPackage: isPackage ?? value.isPackage,
            isLocalVolume: isLocalVolume ?? value.isLocalVolume,
            isReadOnlyVolume: isReadOnlyVolume ?? value.isReadOnlyVolume,
            isProviderBacked: isProviderBacked ?? value.isProviderBacked
        )
    }
}

private final class CapabilityFixture {
    let directory: URL
    let desktop: URL
    let ledger: EncryptedOperationLedger
    let bookmarks = FakeBookmarkCodec()
    let inspector = FakeRootInspector()
    let scopes = FakeScopeAccessor()
    let store: RootCapabilityStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TydlyCapabilityTests-\(UUID().uuidString)", isDirectory: true)
        desktop = directory.appendingPathComponent("Desktop", isDirectory: true)
        try FileManager.default.createDirectory(
            at: desktop,
            withIntermediateDirectories: true
        )
        ledger = try EncryptedOperationLedger(
            path: directory.appendingPathComponent("ledger.sqlite").path,
            keyStore: CapabilityKeyStore()
        )
        inspector.setInspection(
            for: desktop,
            identity: try RootResourceIdentity(volumeID: "volume", fileID: "desktop")
        )
        let uuidSequence = UUIDSequence()
        store = RootCapabilityStore(
            ledger: ledger,
            bookmarkCodec: bookmarks,
            inspector: inspector,
            scopeAccessor: scopes,
            makeUUID: { uuidSequence.next() }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class FakeBookmarkCodec: SecurityScopedBookmarkCoding, @unchecked Sendable {
    private let lock = NSLock()
    private var sequence = 0
    private var resolutions: [Data: BookmarkResolution] = [:]
    private var latestByURL: [URL: Data] = [:]

    func createBookmark(for url: URL) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        sequence += 1
        let data = Data("bookmark-\(sequence)".utf8)
        resolutions[data] = BookmarkResolution(url: url, isStale: false)
        latestByURL[url] = data
        return data
    }

    func resolveBookmark(_ bookmark: Data) throws -> BookmarkResolution {
        lock.lock()
        defer { lock.unlock() }
        guard let resolution = resolutions[bookmark] else {
            throw RootCapabilityError.bookmarkResolutionFailed
        }
        return resolution
    }

    func markLatestStale(for url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = latestByURL[url] else { return }
        resolutions[data] = BookmarkResolution(url: url, isStale: true)
    }
}

private final class FakeRootInspector: RootResourceInspecting, @unchecked Sendable {
    private let queue = DispatchQueue(label: "FakeRootInspector")
    private var inspections: [URL: RootInspection] = [:]

    func inspect(_ url: URL) async throws -> RootInspection {
        try queue.sync {
            guard let inspection = inspections[url] else {
                throw RootCapabilityError.bindingUnavailable
            }
            return inspection
        }
    }

    func relationship(
        of directory: URL,
        to item: URL
    ) throws -> FileManager.URLRelationship {
        let directoryPath = directory.standardizedFileURL.path
        let itemPath = item.standardizedFileURL.path
        if directoryPath == itemPath { return .same }
        if itemPath.hasPrefix(directoryPath + "/") { return .contains }
        return .other
    }

    func setInspection(for url: URL, identity: RootResourceIdentity) {
        queue.sync {
            inspections[url] = RootInspection(
                displayName: url.lastPathComponent,
                identity: identity,
                isDirectory: true,
                isSymbolicLink: false,
                isPackage: false,
                isLocalVolume: true,
                isReadOnlyVolume: false,
                isProviderBacked: false
            )
        }
    }
}

private final class FakeScopeAccessor: SecurityScopeAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func startAccessing(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        startCount += 1
        return true
    }

    func stopAccessing(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        stopCount += 1
    }
}

private struct CapabilityKeyStore: DatabaseKeyStore {
    private static let key = Data(
        repeating: 0xC3,
        count: KeychainDatabaseKeyStore.keyLength
    )

    func loadOrCreateKey() throws -> Data { Self.key }
    func loadExistingKey() throws -> Data? { Self.key }
    func deleteKey() throws {}
}

private final class UUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt8 = 1

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let uuid = UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, value
        ))
        value &+= 1
        return uuid
    }
}
