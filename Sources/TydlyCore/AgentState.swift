import Foundation

/// The archivist's top-level state. Drives both the menu-bar icon and which body
/// the popover shows. Mirrors README.md §State Management:
/// `observing | working | idle-tidy | needs-decision(count) | paused(until) | error(kind)`.
public enum AgentState: Equatable {
    /// First-run reading pass — "Reading, changing nothing". Blue pulse, files untouched.
    case observing

    /// Actively sorting. `current` is the file being read; `remaining` are queued.
    case working(current: String?, remaining: Int)

    /// Everything is caught up. The icon is quiet and never animates (Rule 8).
    case idleTidy

    /// One or more decisions are waiting on the user. `count` badges the icon amber.
    case needsDecision(count: Int)

    /// Paused by the user. Watch-only, dimmed icon (Rule 9 — nothing is deleted).
    case paused(until: PauseUntil)

    /// Something is broken (Rule 5 — red is for broken only, never "busy").
    case error(ErrorKind)
}

/// What the menu-bar glyph shows. One color each; see DESIGN.md color semantics
/// (green = tidy, blue = working, amber = waiting-on-user, grey = paused, red = broken).
public enum IconState: Equatable {
    case quiet                    // plain glyph, no animation
    case working                  // blue badge dot, 1.6s pulse while analyzing
    case needsYou(count: Int)     // amber count badge
    case paused                   // 40% opacity
    case broken                   // red badge dot
}

public extension AgentState {
    /// The icon presentation for this state. Observing pulses like working
    /// (it is reading), but files never move until the user approves.
    var iconState: IconState {
        switch self {
        case .observing:                 return .working
        case .working:                   return .working
        case .idleTidy:                  return .quiet
        case .needsDecision(let count):  return .needsYou(count: count)
        case .paused:                    return .paused
        case .error:                     return .broken
        }
    }

    /// Whether the icon should be animating. Rule 8: never animate when idle.
    var iconAnimates: Bool {
        switch iconState {
        case .working: return true
        default:       return false
        }
    }
}

/// How long a pause lasts. Rendered in Settings as "Until 5 pm · tomorrow · manually".
public enum PauseUntil: Equatable {
    case time(String)   // e.g. "5 pm"
    case tomorrow
    case manual
}

/// The kinds of breakage Otto surfaces. Held work is never dropped (Rule, Phase 05).
public enum ErrorKind: Equatable {
    /// A destination folder was renamed or deleted; queued moves are held, not lost.
    case brokenDestination(folderName: String, movesOnHold: Int)
}
