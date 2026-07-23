import AppKit
import Foundation

public struct RootAuthorizationRequest: Sendable {
    public let message: String
    public let prompt: String
    public let initialDirectory: URL?
    public let canCreateDirectories: Bool

    public init(
        message: String,
        prompt: String,
        initialDirectory: URL?,
        canCreateDirectories: Bool = false
    ) {
        self.message = message
        self.prompt = prompt
        self.initialDirectory = initialDirectory
        self.canCreateDirectories = canCreateDirectories
    }
}

@MainActor
public struct RootAuthorizationPanel {
    public init() {}

    public func selectDirectory(_ request: RootAuthorizationRequest) throws -> URL {
        let panel = NSOpenPanel()
        panel.message = request.message
        panel.prompt = request.prompt
        panel.directoryURL = request.initialDirectory
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = request.canCreateDirectories
        panel.resolvesAliases = false
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = false

        guard panel.runModal() == .OK, let url = panel.url else {
            throw RootCapabilityError.selectionCancelled
        }
        return url
    }
}
