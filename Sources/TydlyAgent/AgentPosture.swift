import Foundation
import TydlyCore

/// Runtime availability of the on-device system language model.
///
/// `Documentation/PRODUCT_VISION.md`: novel project understanding requires the local model.
/// Anything other than `.available` means Otto is watch-only — never a cloud fallback.
public enum ModelAvailability: Equatable, Sendable {
    case available
    case appleIntelligenceDisabled
    case modelNotReady
    case deviceIneligible
    case unsupportedLocale

    public var isAvailable: Bool { self == .available }
}

/// Why Otto is watching but not proposing. These are stable policy keys, not user-facing
/// copy — the popover composes localized text from them in the UI layer.
///
/// The product requires that the user can tell *which* restraint is in effect; a silent agent
/// reads as a broken one.
public enum WatchOnlyReason: Equatable, Sendable {
    case pausedByUser
    case resting
    case capabilityNeedsReauthorization(RootBindingStatus)
    case unresolvedRepair
    case modelUnavailable(ModelAvailability)
}

/// What the agent is permitted to do right now.
///
/// Posture gates *proposal generation only*. It never authorizes execution: `TydlyCore.Rules`
/// remains the sole authority for that, and `TydlyAgent` never issues an
/// `ExecutionAuthorization`.
public enum AgentPosture: Equatable, Sendable {
    case orchestrating
    case watchOnly(WatchOnlyReason)

    public var isOrchestrating: Bool { self == .orchestrating }

    public var watchOnlyReason: WatchOnlyReason? {
        switch self {
        case .orchestrating:
            return nil
        case let .watchOnly(reason):
            return reason
        }
    }
}

/// Transient system pressure that defers discretionary work. Distinct from `WatchOnlyReason`:
/// pressure delays a sweep, it does not change what Otto is allowed to do.
public enum SystemPressure: String, CaseIterable, Equatable, Sendable {
    case thermal
    case lowPower
    case userActive
}

/// A point-in-time reading of the conditions that gate discretionary work.
///
/// `AGENTS.md`/`DESIGN.md`: sweeps run when the Mac is idle. Foundation's `ProcessInfo`
/// thermal and Low Power Mode APIs are Darwin-only, so the agent takes an injected reading
/// instead of reaching for them directly. That keeps this target pure Foundation and makes
/// every pressure path testable without a Mac.
public struct SystemConditions: Equatable, Sendable {
    public let isThermallyPressured: Bool
    public let isInLowPowerMode: Bool
    public let isUserActive: Bool

    public init(
        isThermallyPressured: Bool = false,
        isInLowPowerMode: Bool = false,
        isUserActive: Bool = false
    ) {
        self.isThermallyPressured = isThermallyPressured
        self.isInLowPowerMode = isInLowPowerMode
        self.isUserActive = isUserActive
    }

    public static let idle = SystemConditions()

    /// The first pressure that should defer a discretionary sweep, or nil when the Mac is
    /// quiet enough to work.
    public var deferringPressure: SystemPressure? {
        if isThermallyPressured { return .thermal }
        if isInLowPowerMode { return .lowPower }
        if isUserActive { return .userActive }
        return nil
    }
}

public protocol SystemConditionsProviding: Sendable {
    func currentConditions() async -> SystemConditions
}

/// Pure posture policy, mirroring the `Rules` style in `TydlyCore`: static, deterministic,
/// and unit-testable without an actor or a Mac.
public enum AgentPolicy {
    /// Resolves the single reason Otto is restrained, in the order the user would expect to
    /// hear it: their own explicit choice first, then billing state, then capability, then a
    /// repair the ledger is holding, then the model.
    public static func posture(
        modelAvailability: ModelAvailability,
        subscription: Subscription,
        capability: RootBindingStatus,
        hasUnresolvedRepair: Bool,
        isPausedByUser: Bool
    ) -> AgentPosture {
        if isPausedByUser {
            return .watchOnly(.pausedByUser)
        }
        // Rule 9 — resting is watch-only and deletes nothing.
        if subscription == .resting {
            return .watchOnly(.resting)
        }
        if capability != .active {
            return .watchOnly(.capabilityNeedsReauthorization(capability))
        }
        // An unresolved repair globally blocks new mutation intent (see SECURITY.md), so
        // there is no honest proposal to make until it is cleared.
        if hasUnresolvedRepair {
            return .watchOnly(.unresolvedRepair)
        }
        if !modelAvailability.isAvailable {
            return .watchOnly(.modelUnavailable(modelAvailability))
        }
        return .orchestrating
    }
}
