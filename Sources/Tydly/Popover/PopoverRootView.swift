import SwiftUI
import TydlyCore

/// The popover content shown from the menu-bar item (MenuBarExtra, `.window` style).
/// A native menu, 290pt wide: status → decisions/today → settings. Routes by `agentState`.
struct PopoverRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.agentState {
            case .idleTidy:
                AllTidyView()
            case .needsDecision:
                DecisionView()
            case .working:
                WorkingView()
            case .observing:
                ObservingView()
            case .paused, .error:
                // Paused (Phase 06) and error bodies (Phase 05) land here next.
                AllTidyView()
            }

            #if DEBUG
            DebugStateBar()
            #endif
        }
        .padding(5)
        .frame(width: Metrics.popoverWidth)
        .background(VisualEffectView(material: .menu))
        .overlay(undoShortcut)
    }

    // ⌘Z undoes the last batch while the popover is open (definition of done). The button
    // is invisible; it exists only to own the keyboard shortcut inside this window.
    private var undoShortcut: some View {
        Button("Undo", action: model.undoLast)
            .keyboardShortcut("z", modifiers: .command)
            .buttonStyle(.plain)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }
}

/// The persona header row: name on the left, state-specific content trailing. Used by the
/// all-tidy and decision states (working/observing lead with a live status row instead).
struct PersonaHeaderRow<Trailing: View>: View {
    let name: String
    var trailing: () -> Trailing

    init(name: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.name = name
        self.trailing = trailing
    }

    var body: some View {
        MenuRow {
            Text(name).font(Typography.menuTitle)
            Spacer(minLength: 8)
            trailing()
        }
    }
}

/// A leading status row: pulsing dot + bold status line (working/observing headers).
struct StatusHeaderRow: View {
    let color: Color
    let title: String
    var pulsing: Bool = true

    var body: some View {
        MenuRow {
            StatusDot(color: color, pulsing: pulsing)
            Text(title).font(Typography.menuTitle)
            Spacer(minLength: 0)
        }
    }
}

/// The single reassurance sentence a surface is allowed (Voice rule 3).
struct FooterNote: View {
    let text: String
    var body: some View {
        MenuRow {
            Text(text)
                .font(Typography.meta)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: 0)
        }
    }
}
