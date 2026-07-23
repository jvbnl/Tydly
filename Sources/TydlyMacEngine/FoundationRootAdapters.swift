import FileProvider
import Foundation
import TydlyCore

public struct FoundationBookmarkCodec: SecurityScopedBookmarkCoding {
    public init() {}

    public func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [
                .volumeIdentifierKey,
                .fileResourceIdentifierKey
            ],
            relativeTo: nil
        )
    }

    public func resolveBookmark(_ bookmark: Data) throws -> BookmarkResolution {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return BookmarkResolution(url: url, isStale: isStale)
    }
}

public struct FoundationSecurityScopeAccessor: SecurityScopeAccessing {
    public init() {}

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

public struct FoundationRootInspector: RootResourceInspecting {
    public init() {}

    public func inspect(_ url: URL) async throws -> RootInspection {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isPackageKey,
            .isUbiquitousItemKey,
            .localizedNameKey,
            .volumeIdentifierKey,
            .fileResourceIdentifierKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey
        ])

        let volumeID = try Self.opaqueIdentifier(values.volumeIdentifier)
        let fileID = try Self.opaqueIdentifier(values.fileResourceIdentifier)
        let providerBacked = values.isUbiquitousItem == true
            || await isManagedByFileProvider(url)

        return RootInspection(
            displayName: values.localizedName ?? url.lastPathComponent,
            identity: try RootResourceIdentity(volumeID: volumeID, fileID: fileID),
            isDirectory: values.isDirectory == true,
            isSymbolicLink: values.isSymbolicLink == true,
            isPackage: values.isPackage == true,
            isLocalVolume: values.volumeIsLocal == true,
            isReadOnlyVolume: values.volumeIsReadOnly != false,
            isProviderBacked: providerBacked
        )
    }

    public func relationship(
        of directory: URL,
        to item: URL
    ) throws -> FileManager.URLRelationship {
        var relationship = FileManager.URLRelationship.other
        try FileManager.default.getRelationship(
            &relationship,
            ofDirectoryAt: directory,
            toItemAt: item
        )
        return relationship
    }

    private func isManagedByFileProvider(_ url: URL) async -> Bool {
        do {
            _ = try await NSFileProviderManager.identifierForUserVisibleFile(at: url)
            return true
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError {
            return false
        } catch {
            // An unknown provider query failure is not proof that a location is local.
            return true
        }
    }

    private static func opaqueIdentifier(_ value: Any?) throws -> String {
        let identifier: String
        switch value {
        case let data as Data:
            identifier = data.base64EncodedString()
        case let data as NSData:
            identifier = (data as Data).base64EncodedString()
        case let uuid as UUID:
            identifier = uuid.uuidString
        case let string as String:
            identifier = string
        case let number as NSNumber:
            identifier = number.stringValue
        case .some(let value):
            identifier = String(describing: value)
        case nil:
            throw RootCapabilityError.bindingUnavailable
        }
        guard !identifier.isEmpty else {
            throw RootCapabilityError.bindingUnavailable
        }
        return identifier
    }
}
