import AppKit
import SwiftUI
import TydlyCore

extension Notification.Name {
    /// Posted to (re)present the onboarding card — on first launch and from the debug bar.
    static let tydlyShowOnboarding = Notification.Name("tydly.showOnboarding")
}

/// Owns the AppKit surfaces that sit outside the MenuBarExtra scene — for now, the floating
/// onboarding window. The whisper-bar `NSPanel` (Phase 04) will be managed here too.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no app-switcher entry. Redundant with LSUIElement,
        // but keeps behavior correct when launched unbundled via `swift run`.
        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showOnboarding),
            name: .tydlyShowOnboarding,
            object: nil
        )

        if !AppModel.shared.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    @objc func showOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = OnboardingView(onFinish: { [weak self] in self?.dismissOnboarding() })
            .environmentObject(AppModel.shared)

        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        // A titled window (so the text field can become key) with all chrome hidden and a
        // clear background — only the glass card and its shadow show, floating over the desktop.
        window.styleMask = [.titled, .fullSizeContentView, .closable]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.center()

        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
    }
}
