import Foundation

// MARK: - Autonomy

/// The trust ladder a category climbs. README §State Management:
/// `observe → propose → trusted-rule → auto`. Sensitive categories are permanently
/// capped at `.propose` (Rule 2) — enforced in `Rules`, not just by convention.
public enum AutonomyLevel: Int, Comparable, CaseIterable, Equatable, Sendable {
    case observe = 0
    case propose = 1
    case trustedRule = 2
    case auto = 3

    public static func < (lhs: AutonomyLevel, rhs: AutonomyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - File vocabulary

/// A stable key for a kind of file. Display copy (singular/plural, localized) lives in
/// the UI layer — Core never holds user-facing English so localization stays in one place.
public enum FileKind: String, Equatable, CaseIterable, Sendable {
    case screenshot
    case invoice
    case deck
    case document
    case installer
    case file
}

/// The verb in a log receipt. Otto speaks in receipts: verb + count + destination.
public enum Verb: String, Equatable, Sendable {
    case filed
    case archived
    case undone
}

/// Live per-file status while a sweep runs.
public enum WorkStatus: Equatable, Sendable {
    case reading
    case queued
    case done
}

// MARK: - Project

/// A project Otto files into. Color is deterministic per project (DESIGN.md) so the
/// same project always gets the same avatar/accent — the index maps into the four-color
/// palette held by the UI.
public struct Project: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var colorIndex: Int

    public init(id: String, name: String, colorIndex: Int? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex ?? AvatarPalette.index(for: id)
    }

    /// First letter, used for the circular avatar.
    public var initial: String { String(name.prefix(1)).uppercased() }
}

/// Deterministic mapping from a stable key to one of the four project-avatar colors.
/// Uses FNV-1a (not `Hasher`, which is randomized per process) so the color is stable
/// across launches.
public enum AvatarPalette {
    public static let count = 4

    public static func index(for key: String) -> Int {
        var hash: UInt64 = 1469598103934665603 // FNV-1a offset basis
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211        // FNV prime
        }
        return Int(hash % UInt64(count))
    }
}

// MARK: - Rules / categories

/// A learned filing rule for one category. Carries the trust state that the autonomy
/// ladder and self-demotion operate on. `isSensitive` rows can never become auto (Rule 2).
public struct FilingRule: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var kind: FileKind
    public var destination: Project?
    public internal(set) var autonomy: AutonomyLevel
    /// 0…1. Green ≥ 0.85, amber below (never shown as a percentage — Rule/Voice).
    public var confidence: Double
    public var acceptsInARow: Int
    public var filedCount: Int
    public var undoneCount: Int
    public var mistakesThisWeek: Int
    public internal(set) var isSensitive: Bool
    public internal(set) var revision: Int

    public init(
        id: String,
        name: String,
        kind: FileKind,
        destination: Project? = nil,
        autonomy: AutonomyLevel = .propose,
        confidence: Double = 0,
        acceptsInARow: Int = 0,
        filedCount: Int = 0,
        undoneCount: Int = 0,
        mistakesThisWeek: Int = 0,
        isSensitive: Bool = false,
        revision: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.destination = destination
        self.autonomy = min(autonomy, isSensitive ? .propose : .auto)
        self.confidence = confidence
        self.acceptsInARow = acceptsInARow
        self.filedCount = filedCount
        self.undoneCount = undoneCount
        self.mistakesThisWeek = mistakesThisWeek
        self.isSensitive = isSensitive
        self.revision = max(0, revision)
    }
}

// MARK: - Decisions / parking

/// A proposed group of files awaiting the user's yes. Rendered as the decision card.
public struct Decision: Identifiable, Equatable, Sendable {
    public let id: String
    public var count: Int
    public var kind: FileKind
    public var project: Project
    /// Optional sub-path shown as "Atlas › Screens".
    public var subfolder: String?
    public var confidence: Double
    /// The one line revealed by "why?" (Voice: reasons on demand).
    public var reason: String
    public var skipCount: Int
    public var isSensitive: Bool

    public init(
        id: String,
        count: Int,
        kind: FileKind,
        project: Project,
        subfolder: String? = nil,
        confidence: Double,
        reason: String,
        skipCount: Int = 0,
        isSensitive: Bool = false
    ) {
        self.id = id
        self.count = count
        self.kind = kind
        self.project = project
        self.subfolder = subfolder
        self.confidence = confidence
        self.reason = reason
        self.skipCount = skipCount
        self.isSensitive = isSensitive
    }
}

/// A decision the user skipped enough times to self-mute (Rule 10). Parked items
/// re-ask once on Friday, then go silent.
public struct ParkedItem: Identifiable, Equatable, Sendable {
    public let id: String
    public var reAskWeekdayLabel: String   // e.g. "Fri"
    public var silenced: Bool

    public init(id: String, reAskWeekdayLabel: String = "Fri", silenced: Bool = false) {
        self.id = id
        self.reAskWeekdayLabel = reAskWeekdayLabel
        self.silenced = silenced
    }
}

// MARK: - Log

/// One receipt in the "Today" log. Every row is verb + count + kind + destination chip,
/// individually undoable, and part of a batch that can be undone as a whole (Rule 3).
public struct ActionLogEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public var verb: Verb
    public var count: Int
    public var kind: FileKind
    public var destination: Project
    public var batchID: String
    public var timestamp: Date
    public var undone: Bool

    public init(
        id: String,
        verb: Verb,
        count: Int,
        kind: FileKind,
        destination: Project,
        batchID: String,
        timestamp: Date = Date(),
        undone: Bool = false
    ) {
        self.id = id
        self.verb = verb
        self.count = count
        self.kind = kind
        self.destination = destination
        self.batchID = batchID
        self.timestamp = timestamp
        self.undone = undone
    }
}

// MARK: - Live work

/// A single file in the live sweep queue shown in the Working popover.
public struct WorkingItem: Identifiable, Equatable, Sendable {
    public let id: String
    public var filename: String
    public var status: WorkStatus

    public init(id: String, filename: String, status: WorkStatus) {
        self.id = id
        self.filename = filename
        self.status = status
    }
}

// MARK: - Persona & scope

/// The user-named archivist persona. Default suggestion "Otto"; falls back to
/// "Archivist" if onboarding's naming step is skipped (README Phase 01).
public struct Persona: Equatable, Sendable {
    public var name: String
    public var colorIndex: Int

    public static let suggestedName = "Otto"
    public static let fallbackName = "Archivist"
    public static let nameSuggestions = ["Otto", "Ada", "Juno"]

    public init(name: String = Persona.suggestedName, colorIndex: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
    }
}

/// Which of the two allowed folders Otto may watch. The rest of the Mac stays
/// off-limits — least privilege, stated in onboarding's button copy.
public struct FolderScope: Equatable, Sendable {
    public var desktop: Bool
    public var downloads: Bool

    public init(desktop: Bool = true, downloads: Bool = true) {
        self.desktop = desktop
        self.downloads = downloads
    }

    public var allowedCount: Int { (desktop ? 1 : 0) + (downloads ? 1 : 0) }
}

// MARK: - Subscription

/// Billing state. `resting` = watch-only after a declined trial; all data retained
/// (Rule 9 — decline deletes nothing).
public enum Subscription: Equatable, Sendable {
    case trial(daysLeft: Int)
    case active
    case resting
}
