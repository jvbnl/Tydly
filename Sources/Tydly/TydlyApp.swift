import SwiftUI
import TydlyCore

/// Tydly's entry point. A single `MenuBarExtra` scene (window style, so it can host the
/// rich popover) plus an AppKit delegate for the onboarding window. The whole app is a
/// menu-bar agent — the icon, popover, and (later) whisper bar are the only surfaces.
@main
struct TydlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    init() {
        SecuritySelfTest.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environmentObject(model)
        } label: {
            // Observing `model` here means the label re-renders as the icon state changes.
            MenuBarLabel(state: model.iconState)
        }
        .menuBarExtraStyle(.window)
    }
}
