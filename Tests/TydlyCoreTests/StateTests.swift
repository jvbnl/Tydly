import XCTest
import TydlyCore

/// State-machine and presentation invariants that back product rules 5 and 8, plus the
/// deterministic project palette.
final class StateTests: XCTestCase {

    // MARK: Rule 8 — the icon never animates when idle

    func testOnlyWorkingAndObservingAnimate() {
        XCTAssertFalse(AgentState.idleTidy.iconAnimates, "idle must be perfectly still")
        XCTAssertFalse(AgentState.needsDecision(count: 1).iconAnimates)
        XCTAssertFalse(AgentState.paused(until: .manual).iconAnimates)
        XCTAssertFalse(AgentState.error(.brokenDestination(folderName: "Atlas", movesOnHold: 3)).iconAnimates)

        XCTAssertTrue(AgentState.working(current: nil, remaining: 3).iconAnimates)
        XCTAssertTrue(AgentState.observing.iconAnimates, "observing pulses — it is reading")
    }

    // MARK: Rule 5 — color mapping is exclusive (amber for waiting, red only for broken)

    func testIconStateMapping() {
        XCTAssertEqual(AgentState.idleTidy.iconState, .quiet)
        XCTAssertEqual(AgentState.working(current: nil, remaining: 1).iconState, .working)
        XCTAssertEqual(AgentState.observing.iconState, .working)
        XCTAssertEqual(AgentState.needsDecision(count: 2).iconState, .needsYou(count: 2))
        XCTAssertEqual(AgentState.paused(until: .tomorrow).iconState, .paused)

        if case .broken = AgentState.error(.brokenDestination(folderName: "Atlas", movesOnHold: 3)).iconState {
            // expected
        } else {
            XCTFail("errors map to the red broken badge, and nothing else does")
        }
    }

    // MARK: Deterministic project palette

    func testAvatarPaletteIsStableAndInRange() {
        let a = AvatarPalette.index(for: "atlas")
        let b = AvatarPalette.index(for: "atlas")
        XCTAssertEqual(a, b, "same project always gets the same color across runs")
        XCTAssertTrue((0..<AvatarPalette.count).contains(a))
    }

    func testFolderScopeCount() {
        XCTAssertEqual(FolderScope(desktop: true, downloads: true).allowedCount, 2)
        XCTAssertEqual(FolderScope(desktop: true, downloads: false).allowedCount, 1)
        XCTAssertEqual(FolderScope(desktop: false, downloads: false).allowedCount, 0)
    }
}
