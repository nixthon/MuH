import AppKit

final class LinkHintTooltip {
    private var label: NSTextField?

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
        blur.material = .toolTip
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 5
        blur.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.isBordered = false
        blur.addSubview(label)

        w.contentView = blur
        self.label = label
        return w
    }()

    func show(_ text: String, at screenPoint: NSPoint) {
        _ = window
        guard let label else { return }
        label.stringValue = text
        label.sizeToFit()

        let padX: CGFloat = 8
        let padY: CGFloat = 5
        let size = NSSize(
            width: label.frame.width + padX * 2,
            height: label.frame.height + padY * 2
        )
        label.setFrameOrigin(NSPoint(x: padX, y: padY))
        window.setContentSize(size)
        window.contentView?.frame = NSRect(origin: .zero, size: size)
        window.setFrameOrigin(NSPoint(x: screenPoint.x + 12,
                                      y: screenPoint.y - size.height - 12))
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }
}
