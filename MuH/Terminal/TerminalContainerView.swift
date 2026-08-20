import AppKit

final class TerminalContainerView: NSView {
    var store: HostStore?
    var interactive: Bool = true {
        didSet {
            if !interactive {
                GhosttyTerminalView.makeFrontmost(nil)
            } else if let selectedId = store?.selectedId, let term = terminalViews[selectedId] {
                GhosttyTerminalView.makeFrontmost(term)
                window?.makeFirstResponder(term)
            }
        }
    }

    private var terminalViews: [UUID: GhosttyTerminalView] = [:]
    private var visibleHostId: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = DT.Radius.card
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        for sub in subviews {
            sub.frame = bounds
        }
    }

    func update(hosts: [HostItem], selectedId: UUID?, interactive: Bool = true) {
        self.interactive = interactive
        let liveIds = Set(hosts.map(\.id))
        for id in terminalViews.keys where !liveIds.contains(id) {
            terminalViews[id]?.removeFromSuperview()
            terminalViews.removeValue(forKey: id)
        }

        guard let selectedId, let host = hosts.first(where: { $0.id == selectedId }) else {
            GhosttyTerminalView.makeFrontmost(nil)
            visibleHostId = nil
            return
        }

        let termView: GhosttyTerminalView
        if let existing = terminalViews[selectedId] {
            termView = existing
        } else {
            let created = GhosttyTerminalView(frame: bounds)
            created.hostId = host.id
            created.command = host.defaultCommand
            terminalViews[selectedId] = created
            termView = created
        }

        if visibleHostId != selectedId {
            visibleHostId = selectedId
            subviews.forEach { $0.removeFromSuperview() }
            termView.frame = bounds
            addSubview(termView)
            if interactive {
                GhosttyTerminalView.makeFrontmost(termView)
                window?.makeFirstResponder(termView)
            }
        } else {
            termView.frame = bounds
            if interactive {
                GhosttyTerminalView.makeFrontmost(termView)
            }
        }
    }
}
