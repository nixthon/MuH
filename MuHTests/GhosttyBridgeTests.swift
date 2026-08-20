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

    func testGhosttyConfigDiagnosticsWithCopyOnSelect() {
        let ok = GhosttyBridge.shared.initialize()
        XCTAssertTrue(ok)

        let dummyView = GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.contentView = dummyView
        window.makeKeyAndOrderFront(nil)

        guard let surface = dummyView.rawSurface else {
            XCTFail("surface is nil")
            return
        }

        // Clear clipboard
        NSPasteboard.general.clearContents()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Select all
            let selAll = "select_all"
            _ = selAll.withCString {
                ghostty_surface_binding_action(surface, $0, UInt(selAll.utf8.count))
            }

            let pbAfterSelect = NSPasteboard.general.string(forType: .string)
            XCTAssertFalse(pbAfterSelect?.isEmpty ?? true, "Clipboard should have selected text")

            // Simulate a single click (which deselects and sends empty data)
            let zeroMods = ghostty_input_mods_e(rawValue: 0)
            ghostty_surface_mouse_pos(surface, 50, 50, zeroMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, zeroMods)
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, zeroMods)

            let pbAfterClick = NSPasteboard.general.string(forType: .string)
            XCTAssertEqual(pbAfterClick, pbAfterSelect, "Clipboard should NOT be wiped out by single click / deselection")

            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }
}
