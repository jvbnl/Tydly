import FileProvider
import Foundation
import TydlyCore

public struct FoundationTrustedRootLocator: TrustedRootLocating {
    public init() {}

    public func requiredURL(for purpose: RootPurpose) -> URL? {
        switch purpose {
        case .sourceDesktop:
            return FileManager.default.urls(
                for: .desktopDirectory,
                in: .userDomainMask
            ).first
        case .sourceDownloads:
            return FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first
        case .destination, .legacy:
            return nil
        }
    }

    public var forbiddenBroadRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/", isDirectory: true),
            URL(fileURLWithPath: "/Users", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Library", isDirectory: true),
            URL(fileURLWithPath: "/System", isDirectory: true),
            URL(fileURLWithPath: "/private", isDirectory: true),
            URL(fileURLWithPath: "/Volumes", isDirectory: true),
            home,
            home.appendingPathComponent("Library", isDirectory: true),
            home.appendingPathComponent("Library/CloudStorage", isDirectory: true),
            home.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        ]
    }
}

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
            .volumeURLKey,
            .fileResourceIdentifierKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey
        ])

        let volumeID = try Self.opaqueIdentifier(values.volumeIdentifier)
        let fileID = try Self.opaqueIdentifier(values.fileResourceIdentifier)
        let managedByFileProvider = await isManagedByFileProvider(url)
        let providerBacked = values.isUbiquitousItem == true || managedByFileProvider
        let isVolumeRoot: Bool
        if let volumeURL = values.volume {
            isVolumeRoot = try relationship(of: volumeURL, to: url) == .same
        } else {
            isVolumeRoot = true
        }

        return RootInspection(
            displayName: values.localizedName ?? url.lastPathComponent,
            identity: try RootResourceIdentity(volumeID: volumeID, fileID: fileID),
            isDirectory: values.isDirectory == true,
            isSymbolicLink: values.isSymbolicLink == true,
            isPackage: values.isPackage == true,
            isLocalVolume: values.volumeIsLocal == true,
            isReadOnlyVolume: values.volumeIsReadOnly != false,
            isProviderBacked: providerBacked,
            isVolumeRoot: isVolumeRoot
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
            guard let secureValue = value as? NSSecureCoding else {
                throw RootCapabilityError.bindingUnavailable
            }
            identifier = try NSKeyedArchiver.archivedData(
                withRootObject: secureValue,
                requiringSecureCoding: true
            ).base64EncodedString()
        case nil:
            throw RootCapabilityError.bindingUnavailable
        }
        guard !identifier.isEmpty else {
            throw RootCapabilityError.bindingUnavailable
        }
        return identifier
    }
}
