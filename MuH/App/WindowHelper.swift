import SwiftUI
import AppKit

enum WindowHelper {
    /// 执行系统标题栏双击动作（读取 macOS 系统偏好设置 AppleActionOnDoubleClick）
    static func performDoubleClickAction(on window: NSWindow) {
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize":
            window.miniaturize(nil)
        case "None", "Off":
            break
        case "Maximize", "Fill", "Zoom":
            fallthrough
        default:
            window.performZoom(nil)
        }
    }
}

/// 一个可作为窗口标题栏或背景拖拽区使用的 NSView，支持单指拖拽移动窗口，以及双击触发系统双击动作（最大化/缩放/最小化）。
final class WindowDraggableNSView: NSView {
    var doubleClickAction: (() -> Void)?

    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint: NSPoint = .zero

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastClickTime
        let pt = event.locationInWindow
        let dx = pt.x - lastClickPoint.x
        let dy = pt.y - lastClickPoint.y
        let isManualDoubleClick = dt < NSEvent.doubleClickInterval && (dx * dx + dy * dy < 25)

        if event.clickCount == 2 || isManualDoubleClick {
            lastClickTime = 0
            if let customAction = doubleClickAction {
                customAction()
            } else if let window = self.window {
                WindowHelper.performDoubleClickAction(on: window)
            }
            return
        }

        lastClickTime = now
        lastClickPoint = pt

        guard let window = self.window else {
            super.mouseDown(with: event)
            return
        }
        window.performDrag(with: event)
    }
}

struct WindowDraggableArea: NSViewRepresentable {
    var doubleClickAction: (() -> Void)? = nil

    func makeNSView(context: Context) -> WindowDraggableNSView {
        let view = WindowDraggableNSView()
        view.doubleClickAction = doubleClickAction
        return view
    }

    func updateNSView(_ nsView: WindowDraggableNSView, context: Context) {
        nsView.doubleClickAction = doubleClickAction
    }
}

extension View {
    func windowDraggable(doubleClickAction: (() -> Void)? = nil) -> some View {
        background(WindowDraggableArea(doubleClickAction: doubleClickAction))
    }
}
