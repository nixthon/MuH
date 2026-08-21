import XCTest
import AppKit
@testable import MuH

private final class MockWindow: NSWindow {
    var performZoomCalled = false
    var miniaturizeCalled = false

    override func performZoom(_ sender: Any?) {
        performZoomCalled = true
    }

    override func miniaturize(_ sender: Any?) {
        miniaturizeCalled = true
    }
}

final class WindowHelperTests: XCTestCase {
    private var originalSetting: Any?

    override func setUp() {
        super.setUp()
        originalSetting = UserDefaults.standard.object(forKey: "AppleActionOnDoubleClick")
    }

    override func tearDown() {
        if let original = originalSetting {
            UserDefaults.standard.set(original, forKey: "AppleActionOnDoubleClick")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleActionOnDoubleClick")
        }
        super.tearDown()
    }

    func testPerformDoubleClickActionDefaultsToMaximize() {
        UserDefaults.standard.removeObject(forKey: "AppleActionOnDoubleClick")
        let window = MockWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        WindowHelper.performDoubleClickAction(on: window)

        XCTAssertTrue(window.performZoomCalled)
        XCTAssertFalse(window.miniaturizeCalled)
    }

    func testPerformDoubleClickActionWithExplicitMaximizeOrFillOrZoom() {
        for action in ["Maximize", "Fill", "Zoom"] {
            UserDefaults.standard.set(action, forKey: "AppleActionOnDoubleClick")
            let window = MockWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            WindowHelper.performDoubleClickAction(on: window)

            XCTAssertTrue(window.performZoomCalled, "Expected performZoom for action: \(action)")
            XCTAssertFalse(window.miniaturizeCalled, "Expected no miniaturize for action: \(action)")
        }
    }

    func testPerformDoubleClickActionWithMinimize() {
        UserDefaults.standard.set("Minimize", forKey: "AppleActionOnDoubleClick")
        let window = MockWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        WindowHelper.performDoubleClickAction(on: window)

        XCTAssertFalse(window.performZoomCalled)
        XCTAssertTrue(window.miniaturizeCalled)
    }

    func testPerformDoubleClickActionWithNone() {
        for action in ["None", "Off"] {
            UserDefaults.standard.set(action, forKey: "AppleActionOnDoubleClick")
            let window = MockWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )

            WindowHelper.performDoubleClickAction(on: window)

            XCTAssertFalse(window.performZoomCalled, "Expected no performZoom for action: \(action)")
            XCTAssertFalse(window.miniaturizeCalled, "Expected no miniaturize for action: \(action)")
        }
    }

    func testWindowDraggableNSViewProperties() {
        let view = WindowDraggableNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        XCTAssertTrue(view.mouseDownCanMoveWindow)
    }
}
