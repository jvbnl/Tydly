import Foundation
import XCTest
import TydlyCore

final class OperationLedgerTests: XCTestCase {
    func testRelativePathRejectsTraversalAndAbsolutePaths() throws {
        XCTAssertEqual(
            try ScopedRelativePath(rawValue: "Atlas/Screens/shot.png").rawValue,
            "Atlas/Screens/shot.png"
        )

        for invalid in [
            "",
            "/Users/person/Desktop/file",
            "../file",
            "Atlas/../file",
            "Atlas/./file",
            "Atlas//file",
            "Atlas/",
            "Atlas/\0/file"
        ] {
            XCTAssertThrowsError(try ScopedRelativePath(rawValue: invalid), invalid)
        }
    }

    func testPreparedRecoveryIsIdempotentAndFailClosed() {
        XCTAssertEqual(
            LedgerRecovery.action(phase: .prepared, observation: .matchingSourceOnly),
            .retryMutation
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .prepared, observation: .matchingDestinationOnly),
            .markApplied
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .prepared, observation: .matchingSourceAndDestination),
            .holdForRepair(.ambiguousPresence)
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .prepared, observation: .neitherPresent),
            .holdForRepair(.ambiguousPresence)
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .prepared, observation: .conflictingDestination),
            .holdForRepair(.destinationConflict)
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .prepared, observation: .capabilityUnavailable),
            .holdForRepair(.capabilityUnavailable)
        )
    }

    func testAppliedRecoveryOnlyFinalizesMatchingDestination() {
        XCTAssertEqual(
            LedgerRecovery.action(phase: .applied, observation: .matchingDestinationOnly),
            .markCommitted
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .applied, observation: .matchingSourceOnly),
            .retryMutation
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .applied, observation: .neitherPresent),
            .holdForRepair(.missingCommittedItem)
        )
    }

    func testTerminalRecoveryNeverRetriesMutation() {
        XCTAssertEqual(
            LedgerRecovery.action(phase: .committed, observation: .matchingDestinationOnly),
            .none
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .aborted, observation: .matchingSourceOnly),
            .none
        )
        XCTAssertEqual(
            LedgerRecovery.action(phase: .committed, observation: .matchingSourceOnly),
            .holdForRepair(.terminalStateMismatch)
        )

        for observation in [
            FileSystemObservation.matchingSourceOnly,
            .matchingDestinationOnly,
            .matchingSourceAndDestination,
            .neitherPresent,
            .conflictingDestination,
            .capabilityUnavailable
        ] {
            let action = LedgerRecovery.action(phase: .needsRepair, observation: observation)
            switch action {
            case .retryMutation, .markApplied, .markCommitted:
                XCTFail("repair state must not mutate: \(observation)")
            case .markAborted, .holdForRepair, .none:
                break
            }
        }
    }

    func testOnlyForwardCompareAndSwapTransitionsAreAllowed() {
        XCTAssertTrue(LedgerTransition.allows(from: .prepared, to: .applied))
        XCTAssertTrue(LedgerTransition.allows(from: .prepared, to: .aborted))
        XCTAssertTrue(LedgerTransition.allows(from: .prepared, to: .needsRepair))
        XCTAssertTrue(LedgerTransition.allows(from: .applied, to: .committed))
        XCTAssertTrue(LedgerTransition.allows(from: .applied, to: .needsRepair))

        for terminal in [
            LedgerOperationPhase.committed,
            .aborted,
            .needsRepair
        ] {
            for next in LedgerOperationPhase.allCases {
                XCTAssertFalse(LedgerTransition.allows(from: terminal, to: next))
            }
        }
    }

    func testOperationDraftRejectsNegativeOrdinal() throws {
        let identity = try LedgerFileIdentity(
            volumeID: "volume",
            fileID: "file",
            byteCount: 42,
            modifiedAt: Date(timeIntervalSince1970: 1),
            fingerprint: "fingerprint"
        )

        XCTAssertThrowsError(
            try LedgerOperationDraft(
                id: "operation",
                batchID: "batch",
                ordinal: -1,
                kind: .move,
                sourceRootID: "desktop",
                sourcePath: ScopedRelativePath(rawValue: "shot.png"),
                destinationRootID: "atlas",
                destinationPath: ScopedRelativePath(rawValue: "Screens/shot.png"),
                expectedSourceIdentity: identity
            )
        ) {
            XCTAssertEqual($0 as? LedgerValidationError, .negativeOrdinal)
        }
    }
}
