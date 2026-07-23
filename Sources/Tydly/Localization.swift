import Foundation
import TydlyCore

/// All user-facing copy, in one place (CLAUDE.md: strings in a localizable table; Dutch
/// planned next). Base English strings double as the lookup keys; `Localizable.strings`
/// provides the table, and a `nl.lproj` later only has to swap the *values*.
///
/// Composed lines use positional format specifiers (`%1$d`, `%2$@`) so a translation can
/// reorder them. Pluralization here is a simple singular/plural switch — a real pass would
/// move counts into a `.stringsdict`. Copy marked "do not change" in the handoff is kept
/// verbatim.
enum L {
    private static let resourceBundle: Bundle = {
        let bundleName = "Tydly_Tydly.bundle"
        let candidateDirectories = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL
        ].compactMap { $0 }

        for directory in candidateDirectories {
            let url = directory.appendingPathComponent(bundleName, isDirectory: true)
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        // `swift run` keeps the generated bundle beside the executable. Bundle.module
        // remains the authoritative fallback for an unbundled SwiftPM launch.
        return .module
    }()

    private static func s(_ english: String) -> String {
        // Base-English string doubles as the key; `value:` is the fallback when a
        // translation (e.g. a future nl.lproj) is missing.
        NSLocalizedString(english, tableName: "Localizable", bundle: resourceBundle, value: english, comment: "")
    }

    // MARK: File nouns (verb + count + noun receipts)

    static func noun(_ kind: FileKind, count: Int) -> String {
        switch kind {
        case .screenshot: return count == 1 ? s("screenshot") : s("screenshots")
        case .invoice:    return count == 1 ? s("invoice") : s("invoices")
        case .deck:       return count == 1 ? s("deck") : s("decks")
        case .document:   return count == 1 ? s("document") : s("documents")
        case .installer:  return count == 1 ? s("installer") : s("installers")
        case .file:       return count == 1 ? s("file") : s("files")
        }
    }

    // MARK: Popover — all tidy

    static var allTidy: String { s("All tidy") }
    static var today: String { s("Today") }
    static var settings: String { s("Settings…") }

    /// "Filed 3 screenshots" — verb + count + noun.
    static func filedLine(count: Int, kind: FileKind) -> String {
        String(format: s("Filed %1$d %2$@"), count, noun(kind, count: count))
    }

    // MARK: Popover — decision

    static func decisionBadge(_ count: Int) -> String {
        String(format: s(count == 1 ? "%d decision" : "%d decisions"), count)
    }

    /// "12 screenshots → Atlas › Screens". A proposal uses the arrow; receipts use chips.
    static func decisionTitle(_ decision: Decision) -> String {
        var destination = decision.project.name
        if let subfolder = decision.subfolder { destination += " › \(subfolder)" }
        return String(format: s("%1$d %2$@ → %3$@"),
                      decision.count, noun(decision.kind, count: decision.count), destination)
    }

    static var why: String { s("why?") }
    static var showMe: String { s("Show me") }
    static var skip: String { s("Skip") }
    static var decisionFooter: String { s("Nothing moves without you") }

    static func parkedLine(count: Int, day: String) -> String {
        String(format: s("%1$d parked · asks again %2$@"), count, day)
    }

    // MARK: Popover — working / observing

    static func sortingLine(count: Int, location: String) -> String {
        String(format: s("Sorting %1$d in %2$@"), count, location)
    }
    static var working_reading: String { s("reading…") }
    static var working_queued: String { s("queued") }
    static var workingFooter: String { s("Next sweep when your Mac is idle") }

    static var observingTitle: String { s("Reading, changing nothing") }
    static func observingScope(_ scope: FolderScope) -> String {
        let names = [scope.desktop ? s("Desktop") : nil,
                     scope.downloads ? s("Downloads") : nil].compactMap { $0 }
        let list = names.joined(separator: " & ")
        return String(format: s("%@ · a few minutes"), list)
    }

    // MARK: Onboarding

    static var onboarding_privacy_title: String { s("Nothing leaves this Mac") }
    static var onboarding_privacy_sub: String { s("No account. No cloud. No exceptions.") }
    static var onboarding_continue: String { s("Continue") }

    static var onboarding_scope_title: String { s("Where may I work?") }
    static var onboarding_desktop: String { s("Desktop") }
    static var onboarding_downloads: String { s("Downloads") }
    static var onboarding_scope_sub: String { s("The rest of your Mac stays off-limits.") }
    /// Copy = exact scope, do not change (CLAUDE.md).
    static var onboarding_allow: String { s("Allow these 2 folders") }

    static var onboarding_name_title: String { s("Your archivist needs a name") }
    static var onboarding_name_own: String { s("own…") }
    /// Neutral pronoun: the persona is user-named (Otto / Ada / Juno / custom), so "their"
    /// stays correct for every choice. (Mock reads "his"; flagged as a deliberate change.)
    static var onboarding_signs: String { s("Signs their work as") }
    static func onboarding_meet(_ name: String) -> String {
        String(format: s("Meet %@"), name)
    }
}
