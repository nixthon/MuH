import XCTest
@testable import MuH

final class GhosttyBridgeTests: XCTestCase {
    func testResolveOpenURLAllowsSupportedSchemes() {
        XCTAssertEqual(GhosttyBridge.resolveOpenURL("https://example.com")?.scheme, "https")
        XCTAssertEqual(GhosttyBridge.resolveOpenURL("mailto:user@example.com")?.scheme, "mailto")
    }

    func testResolveOpenURLRejectsUnsupportedSchemes() {
        XCTAssertNil(GhosttyBridge.resolveOpenURL("ssh://example.com"))
        XCTAssertNil(GhosttyBridge.resolveOpenURL("javascript:alert(1)"))
    }

    func testResolveOpenURLRejectsEmptyFileURL() {
        XCTAssertNil(GhosttyBridge.resolveOpenURL("file://"))
    }
}
