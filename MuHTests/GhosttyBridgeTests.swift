import XCTest
@testable import MuH

final class GhosttyBridgeTests: XCTestCase {
    // MARK: - Helpers

    /// 创建真实 surface（同现有测试模式）：真实 shell + 真实剪贴板回调链路。
    private func makeTestSurface() -> (view: GhosttyTerminalView, window: NSWindow, surface: ghostty_surface_t)? {
        XCTAssertTrue(GhosttyBridge.shared.initialize())
        let view = GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        guard let surface = view.rawSurface else { return nil }
        return (view, window, surface)
    }

    private func runBinding(_ surface: ghostty_surface_t, _ name: String) {
        _ = name.withCString { ghostty_surface_binding_action(surface, $0, UInt(name.utf8.count)) }
    }

    private func singleClickDeselect(_ surface: ghostty_surface_t) {
        let zeroMods = ghostty_input_mods_e(rawValue: 0)
        ghostty_surface_mouse_pos(surface, 50, 50, zeroMods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, zeroMods)
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, zeroMods)
    }

    // MARK: - URL 解析

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

    // MARK: - 选中即复制（Copy-on-Select）专项

    func testGhosttyConfigDiagnosticsWithCopyOnSelect() {
        guard let ctx = makeTestSurface() else {
            XCTFail("surface is nil")
            return
        }
        let surface = ctx.surface

        // Clear clipboard
        NSPasteboard.general.clearContents()

        let exp = expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Select all
            self.runBinding(surface, "select_all")

            let pbAfterSelect = NSPasteboard.general.string(forType: .string)
            XCTAssertFalse(pbAfterSelect?.isEmpty ?? true, "Clipboard should have selected text")

            // Simulate a single click (which deselects and sends empty data)
            self.singleClickDeselect(surface)

            let pbAfterClick = NSPasteboard.general.string(forType: .string)
            XCTAssertEqual(pbAfterClick, pbAfterSelect, "Clipboard should NOT be wiped out by single click / deselection")

            exp.fulfill()
        }
        wait(for: [exp], timeout: 3.0)
    }

    /// Ghostty 1.4 起 write_clipboard 的 data 为带显式 len 的二进制安全缓冲（不再保证 NUL 结尾）。
    /// 本用例验证选中即复制对多字节 UTF-8（含 4 字节 emoji）的无损往返。
    func testCopyOnSelectPreservesMultibyteUTF8Text() {
        guard let ctx = makeTestSurface() else {
            XCTFail("surface is nil")
            return
        }
        let surface = ctx.surface
        // 汉字 + 4 字节 emoji + 日文假名 + ASCII 混合
        let marker = "汉宇🎉コピーMuH_多字节选中测试"

        let exp = expectation(description: "utf8 roundtrip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 用 1.4 新 API 直接注入文本到 pty（不经过剪贴板，保证注入内容确定性）
            marker.withCString { ptr in
                ghostty_surface_paste_text(surface, ptr, UInt(marker.utf8.count))
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSPasteboard.general.clearContents()
                self.runBinding(surface, "select_all")

                let copied = NSPasteboard.general.string(forType: .string)
                XCTAssertTrue(copied?.contains(marker) ?? false,
                              "选中即复制应无损往返多字节 UTF-8（含 4 字节 emoji），实际: \(copied ?? "<nil>")")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 8.0)
    }

    /// 抑制写入（suppressClipboardWrites）期间，选中即复制不得改动系统剪贴板；解除后应恢复写入。
    func testCopyOnSelectSuppressionGuard() {
        guard let ctx = makeTestSurface() else {
            XCTFail("surface is nil")
            return
        }
        let surface = ctx.surface
        let sentinel = "MUH_SUPPRESS_SENTINEL_4821"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sentinel, forType: .string)

        let exp = expectation(description: "suppression")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            GhosttyBridge.suppressClipboardWrites = true
            self.runBinding(surface, "select_all")
            let afterSuppressed = NSPasteboard.general.string(forType: .string)
            GhosttyBridge.suppressClipboardWrites = false
            XCTAssertEqual(afterSuppressed, sentinel,
                           "抑制写入时选中即复制不得改动系统剪贴板")

            // 先取消选择，再重新全选以重新触发 copy-on-select
            self.singleClickDeselect(surface)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.runBinding(surface, "select_all")
                let afterResume = NSPasteboard.general.string(forType: .string)
                XCTAssertNotEqual(afterResume, sentinel,
                                  "解除抑制后选中即复制应恢复写剪贴板")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 8.0)
    }

    /// 粘贴完整链路：系统剪贴板 → 新版 read 回调（MIME 协商 + complete 请求）→ pty → 屏幕。
    /// 用 read_selection 读回屏幕文本验证，避免验证本身污染剪贴板。
    func testPasteFromClipboardDeliversTextToTerminal() {
        guard let ctx = makeTestSurface() else {
            XCTFail("surface is nil")
            return
        }
        let surface = ctx.surface
        let probe = "MUH_PASTE_probe_9f2c"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(probe, forType: .string)

        let exp = expectation(description: "paste roundtrip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.runBinding(surface, "paste_from_clipboard")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.runBinding(surface, "select_all")
                var text = ghostty_text_s()
                guard ghostty_surface_read_selection(surface, &text), let ptr = text.text else {
                    XCTFail("read_selection 失败")
                    exp.fulfill()
                    return
                }
                let data = Data(bytes: UnsafeRawPointer(ptr), count: Int(text.text_len))
                ghostty_surface_free_text(surface, &text)
                let screen = String(data: data, encoding: .utf8) ?? ""
                XCTAssertTrue(screen.contains(probe),
                              "粘贴应通过新版 read 回调（MIME 协商）完整送达终端，实际屏幕前 200 字符: \(screen.prefix(200))")
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 10.0)
    }
}
