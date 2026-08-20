import AppKit

/// Transient HUD tooltip shown when text is copied to the clipboard.
final class CopyToastHUD {
    static let shared = CopyToastHUD()

    private var hideWorkItem: DispatchWorkItem?
    private var label: NSTextField?
    private var iconView: NSImageView?

    private lazy var window: NSWindow = {
        let w = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .floating
        w.ignoresMouseEvents = true
        w.hasShadow = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        icon.contentTintColor = .systemGreen
        blur.addSubview(icon)

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBordered = false
        blur.addSubview(label)

        w.contentView = blur
        self.label = label
        self.iconView = icon
        return w
    }()

    func show(text: String? = nil, at screenPoint: NSPoint? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show(text: text, at: screenPoint)
            }
            return
        }

        hideWorkItem?.cancel()
        _ = window
        guard let label, let iconView else { return }

        let displayString = text ?? L10n.string("terminal.copied.toast")
        label.stringValue = displayString
        label.sizeToFit()

        let iconSize: CGFloat = 16
        let padX: CGFloat = 12
        let padY: CGFloat = 6
        let spacing: CGFloat = 6

        let totalWidth = padX + iconSize + spacing + label.frame.width + padX
        let totalHeight = max(iconSize, label.frame.height) + padY * 2
        let size = NSSize(width: totalWidth, height: totalHeight)

        iconView.frame = NSRect(x: padX, y: (totalHeight - iconSize) / 2, width: iconSize, height: iconSize)
        label.frame = NSRect(x: padX + iconSize + spacing, y: (totalHeight - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)

        window.setContentSize(size)
        window.contentView?.frame = NSRect(origin: .zero, size: size)

        let origin: NSPoint
        if let pt = screenPoint {
            origin = NSPoint(x: pt.x + 12, y: pt.y - size.height - 12)
        } else if let mainScreen = NSScreen.main {
            origin = NSPoint(x: mainScreen.frame.midX - size.width / 2, y: mainScreen.frame.midY + 100)
        } else {
            origin = NSEvent.mouseLocation
        }
        window.setFrameOrigin(origin)
        window.alphaValue = 1.0
        window.orderFront(nil)

        let workItem = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                self?.window.animator().alphaValue = 0.0
            }, completionHandler: {
                self?.window.orderOut(nil)
                self?.window.alphaValue = 1.0
            })
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        window.orderOut(nil)
    }
}
