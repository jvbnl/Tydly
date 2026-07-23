import XCTest
import TydlyCore

final class RootCapabilityTests: XCTestCase {
    func testRootGenerationRequiresStableIdentifiersAndMonotonicIndex() throws {
        let identity = try RootResourceIdentity(volumeID: "volume", fileID: "file")
        let descriptor = try RootGenerationDescriptor(
            id: "desktop-g0",
            logicalRootID: "desktop",
            generation: 0,
            purpose: .sourceDesktop,
            displayName: "Desktop",
            identity: identity
        )
        XCTAssertEqual(descriptor.generation, 0)
        XCTAssertEqual(descriptor.identity, identity)

        XCTAssertThrowsError(
            try RootGenerationDescriptor(
                id: "desktop-g-1",
                logicalRootID: "desktop",
                generation: -1,
                purpose: .sourceDesktop,
                displayName: "Desktop",
                identity: identity
            )
        ) {
            XCTAssertEqual($0 as? RootCapabilityValidationError, .negativeGeneration)
        }
    }

    func testRootIdentityRejectsMissingOpaqueValues() {
        XCTAssertThrowsError(try RootResourceIdentity(volumeID: "", fileID: "file"))
        XCTAssertThrowsError(try RootResourceIdentity(volumeID: "volume", fileID: ""))
    }
}
