import SwiftUI
import AppKit

struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let w = v.window { configure(w) }
        }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let w = nsView.window { configure(w) }
        }
    }
}

extension View {
    func muhFullSizeContent(
        backgroundOpacity: CGFloat = 1.0,
        blurRadius: CGFloat = 0,
        onWindow: @escaping (NSWindow) -> Void = { _ in }
    ) -> some View {
        background(
            WindowAccessor { window in
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                if let toolbar = window.toolbar {
                    toolbar.isVisible = false
                }
                let opaque = backgroundOpacity >= 1.0
                window.isOpaque = opaque
                window.backgroundColor = opaque ? nil : .clear
                window.hasShadow = true
                _ = blurRadius
                if let contentView = window.contentView {
                    let titlebarInset = max(0, window.frame.height - window.contentLayoutRect.height)
                    if contentView.additionalSafeAreaInsets.top != -titlebarInset {
                        contentView.additionalSafeAreaInsets = NSEdgeInsets(
                            top: -titlebarInset, left: 0, bottom: 0, right: 0)
                    }
                }
                onWindow(window)
            }
        )
    }
}
