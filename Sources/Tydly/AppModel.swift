import Foundation
import Combine
import TydlyCore

/// The app-wide observable state for the macOS UI. Holds `TydlyCore` value types and the
/// user-facing state machine; the rule *logic* lives in `TydlyCore.Rules`. There is no
/// file engine yet, so intents mutate in-memory state — enough for the scaffold to feel
/// live and for every screen to be reachable.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: Onboarding & persona (persisted)

    @Published var hasCompletedOnboarding: Bool
    @Published var persona: Persona
    @Published var folderScope: FolderScope

    // MARK: Master switch (popover header)

    /// The header toggle. Off = watch-only (paused). Nothing is deleted (Rule 9).
    @Published var isEnabled: Bool = true

    // MARK: Agent state & data

    @Published var agentState: AgentState = .idleTidy
    @Published var decisions: [Decision]
    @Published var todayLog: [ActionLogEntry]
    @Published var workingQueue: [WorkingItem]
    @Published var workingLocation: String = SampleData.workingLocation
    @Published var parkedCount: Int
    @Published var parkedReAskLabel: String = SampleData.parkedReAskLabel
    @Published var subscription: TydlyCore.Subscription = .trial(daysLeft: 30)

    private let defaults: UserDefaults

    private enum Keys {
        static let onboarded = "tydly.onboarded"
        static let personaName = "tydly.persona.name"
        static let personaColor = "tydly.persona.colorIndex"
        static let desktop = "tydly.scope.desktop"
        static let downloads = "tydly.scope.downloads"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarded)
        persona = Persona(
            name: defaults.string(forKey: Keys.personaName) ?? Persona.suggestedName,
            colorIndex: defaults.integer(forKey: Keys.personaColor)
        )
        folderScope = FolderScope(
            desktop: defaults.object(forKey: Keys.desktop) as? Bool ?? true,
            downloads: defaults.object(forKey: Keys.downloads) as? Bool ?? true
        )
        decisions = [SampleData.screenshotDecision]
        todayLog = SampleData.todayLog()
        workingQueue = SampleData.workingQueue
        parkedCount = SampleData.parkedCount
    }

    // MARK: Derived

    /// The menu-bar icon state. When the master switch is off, the icon is always paused.
    var iconState: IconState {
        isEnabled ? agentState.iconState : .paused
    }

    var personaName: String { persona.name }

    // MARK: Intents (in-memory until the file engine lands)

    func toggleEnabled() {
        isEnabled.toggle()
    }

    /// Approve the leading decision: file it, drop a receipt into Today, advance state.
    func approveTopDecision() {
        guard let decision = decisions.first else { return }
        decisions.removeFirst()
        todayLog.insert(
            ActionLogEntry(
                id: "log-\(decision.id)",
                verb: .filed,
                count: decision.count,
                kind: decision.kind,
                destination: decision.project,
                batchID: "batch-\(decision.id)"
            ),
            at: 0
        )
        refreshStateAfterDecisionChange()
    }

    /// Skip the leading decision. Two skips park it and it self-mutes (Rule 10).
    func skipTopDecision() {
        guard var decision = decisions.first else { return }
        if Rules.shouldPark(afterSkipping: decision) {
            parkedCount += 1
            decisions.removeFirst()
        } else {
            decision.skipCount += 1
            decisions[0] = decision
        }
        refreshStateAfterDecisionChange()
    }

    /// Undo the most recent, not-yet-undone receipt (Rule 3 — always available). The
    /// popover binds ⌘Z to this.
    func undoLast() {
        guard let index = todayLog.firstIndex(where: { !$0.undone }) else { return }
        todayLog[index].undone = true
    }

    func undo(_ entry: ActionLogEntry) {
        guard let index = todayLog.firstIndex(where: { $0.id == entry.id }) else { return }
        todayLog[index].undone = true
    }

    private func refreshStateAfterDecisionChange() {
        agentState = decisions.isEmpty ? .idleTidy : .needsDecision(count: decisions.count)
    }

    // MARK: Onboarding

    func completeOnboarding(persona: Persona, scope: FolderScope) {
        self.persona = persona
        self.folderScope = scope
        hasCompletedOnboarding = true
        persist()
        // Trust is set; the first clean begins by observing (Phase 02).
        agentState = .observing
    }

    func skipNaming(scope: FolderScope) {
        completeOnboarding(persona: Persona(name: Persona.fallbackName, colorIndex: 0), scope: scope)
    }

    private func persist() {
        defaults.set(hasCompletedOnboarding, forKey: Keys.onboarded)
        defaults.set(persona.name, forKey: Keys.personaName)
        defaults.set(persona.colorIndex, forKey: Keys.personaColor)
        defaults.set(folderScope.desktop, forKey: Keys.desktop)
        defaults.set(folderScope.downloads, forKey: Keys.downloads)
    }

    // MARK: DEBUG — reach every state without a file engine

    #if DEBUG
    /// The states the in-app debug switcher can jump between (Xcode previews are not part
    /// of the no-Xcode workflow, so this is how you eyeball each screen at runtime).
    enum PreviewState: String, CaseIterable, Identifiable {
        case allTidy, decision, working, observing
        var id: String { rawValue }
        var label: String {
            switch self {
            case .allTidy:   return "All tidy"
            case .decision:  return "Decision"
            case .working:   return "Working"
            case .observing: return "Observing"
            }
        }
    }

    var debugState: PreviewState {
        switch agentState {
        case .idleTidy:      return .allTidy
        case .needsDecision: return .decision
        case .working:       return .working
        case .observing:     return .observing
        default:             return .allTidy
        }
    }

    func debugApply(_ preview: PreviewState) {
        switch preview {
        case .allTidy:
            agentState = .idleTidy
        case .decision:
            if decisions.isEmpty { decisions = [SampleData.screenshotDecision] }
            agentState = .needsDecision(count: decisions.count)
        case .working:
            workingQueue = SampleData.workingQueue
            agentState = .working(current: workingQueue.first?.filename, remaining: workingQueue.count)
        case .observing:
            agentState = .observing
        }
    }

    func debugResetOnboarding() {
        hasCompletedOnboarding = false
        defaults.set(false, forKey: Keys.onboarded)
    }
    #endif
}
