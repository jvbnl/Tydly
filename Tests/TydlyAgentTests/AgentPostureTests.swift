import XCTest
import TydlyAgent
import TydlyCore

final class AgentPostureTests: XCTestCase {
    private func posture(
        model: ModelAvailability = .available,
        subscription: Subscription = .active,
        capability: RootBindingStatus = .active,
        repair: Bool = false,
        paused: Bool = false
    ) -> AgentPosture {
        AgentPolicy.posture(
            modelAvailability: model,
            subscription: subscription,
            capability: capability,
            hasUnresolvedRepair: repair,
            isPausedByUser: paused
        )
    }

    func testHealthyStateOrchestrates() {
        XCTAssertEqual(posture(), .orchestrating)
    }

    // PRODUCT_VISION.md: model unavailable means watch-only, never a cloud fallback.
    func testEveryUnavailableModelStateIsWatchOnly() {
        let unavailable: [ModelAvailability] = [
            .appleIntelligenceDisabled,
            .modelNotReady,
            .deviceIneligible,
            .unsupportedLocale
        ]
        for state in unavailable {
            XCTAssertEqual(
                posture(model: state),
                .watchOnly(.modelUnavailable(state)),
                "\(state) must be watch-only"
            )
        }
    }

    // Rule 9 — resting is watch-only and deletes nothing.
    func testRestingIsWatchOnly() {
        XCTAssertEqual(posture(subscription: .resting), .watchOnly(.resting))
    }

    func testTrialAndActiveBothOrchestrate() {
        XCTAssertEqual(posture(subscription: .trial(daysLeft: 3)), .orchestrating)
        XCTAssertEqual(posture(subscription: .active), .orchestrating)
    }

    func testCapabilityNeedingReauthorizationIsWatchOnly() {
        XCTAssertEqual(
            posture(capability: .needsReauthorization),
            .watchOnly(.capabilityNeedsReauthorization(.needsReauthorization))
        )
        XCTAssertEqual(
            posture(capability: .unsupported),
            .watchOnly(.capabilityNeedsReauthorization(.unsupported))
        )
    }

    func testUnresolvedRepairIsWatchOnly() {
        XCTAssertEqual(posture(repair: true), .watchOnly(.unresolvedRepair))
    }

    // The user's own choice is reported ahead of every other reason.
    func testPauseWinsOverEveryOtherReason() {
        XCTAssertEqual(
            posture(
                model: .appleIntelligenceDisabled,
                subscription: .resting,
                capability: .unsupported,
                repair: true,
                paused: true
            ),
            .watchOnly(.pausedByUser)
        )
    }

    func testRestingIsReportedAheadOfModelAvailability() {
        XCTAssertEqual(
            posture(model: .modelNotReady, subscription: .resting),
            .watchOnly(.resting)
        )
    }

    func testDeferringPressureOrdering() {
        XCTAssertNil(SystemConditions.idle.deferringPressure)
        XCTAssertEqual(
            SystemConditions(isThermallyPressured: true, isInLowPowerMode: true).deferringPressure,
            .thermal
        )
        XCTAssertEqual(
            SystemConditions(isInLowPowerMode: true, isUserActive: true).deferringPressure,
            .lowPower
        )
        XCTAssertEqual(
            SystemConditions(isUserActive: true).deferringPressure,
            .userActive
        )
    }
}
