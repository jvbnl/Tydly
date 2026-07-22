import Foundation

/// Sample state that reproduces the exact content of the Journey mock (phases 02–03).
/// Used to seed the scaffold at runtime — there is no file engine yet — and by previews
/// and tests. All copy here is *data* (names, counts, filenames); user-facing labels and
/// their localization live in the UI layer.
public enum SampleData {

    // Projects (deterministic avatar colors).
    public static let atlas = Project(id: "atlas", name: "Atlas", colorIndex: 0)
    public static let finance = Project(id: "finance", name: "Finance", colorIndex: 1)

    // MARK: Decision waiting (Phase 03)

    public static let screenshotDecision = Decision(
        id: "d-screenshots-atlas",
        count: 12,
        kind: .screenshot,
        project: atlas,
        subfolder: "Screens",
        confidence: 0.92,
        reason: #"Filenames match "atlas-*", saved while you worked on Atlas."#,
        skipCount: 0,
        isSensitive: false
    )

    public static let parkedCount = 4
    public static let parkedReAskLabel = "Fri"

    // MARK: All tidy — today's log (Phase 03)

    public static func todayLog(now: Date = Date()) -> [ActionLogEntry] {
        [
            ActionLogEntry(
                id: "log-screens",
                verb: .filed, count: 3, kind: .screenshot,
                destination: atlas, batchID: "batch-1", timestamp: now
            ),
            ActionLogEntry(
                id: "log-invoice",
                verb: .filed, count: 1, kind: .invoice,
                destination: finance, batchID: "batch-2", timestamp: now
            )
        ]
    }

    // MARK: Working — live sweep (Phase 03)

    public static let workingQueue: [WorkingItem] = [
        WorkingItem(id: "w1", filename: "atlas-flow-v2.png", status: .reading),
        WorkingItem(id: "w2", filename: "Invoice 8841.pdf", status: .queued),
        WorkingItem(id: "w3", filename: "setup.dmg", status: .queued)
    ]

    /// "Sorting 3 in Downloads" — the count is the queue size.
    public static let workingLocation = "Downloads"

    // MARK: Rules (Phase 06, for later — included for a coherent model)

    public static let sampleRules: [FilingRule] = [
        FilingRule(
            id: "r-screenshots", name: "Screenshots → Atlas", kind: .screenshot,
            destination: atlas, autonomy: .auto, confidence: 0.95,
            acceptsInARow: 12, filedCount: 41, undoneCount: 0
        ),
        FilingRule(
            id: "r-sensitive", name: "Sensitive files", kind: .document,
            autonomy: .propose, confidence: 0.5, isSensitive: true
        )
    ]
}
