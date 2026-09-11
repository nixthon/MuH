import AppKit

final class TerminalContainerView: NSView {
    var store: HostStore?
    var interactive: Bool = true {
        didSet {
            guard oldValue != interactive else { return }
            if !interactive {
                GhosttyTerminalView.makeFrontmost(nil)
            } else if let selectedId = store?.selectedId, let term = terminalViews[selectedId] {
                GhosttyTerminalView.makeFrontmost(term)
                focus(term)
            }
        }
    }

    private var terminalViews: [UUID: GhosttyTerminalView] = [:]
    private var visibleHostId: UUID?

    /// 左键点击 Host 仅选中显示，不建立会话；会话只能由右键菜单
    /// 「连接」显式拉起，被「断开」的 Host 在此集合中保持断开态。
    private var disconnectedHosts = Set<UUID>()
    private var theme: AppTheme?

    private let placeholderLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        placeholderLabel.alignment = .center
        placeholderLabel.font = DT.Font.body
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.isHidden = true
        addSubview(placeholderLabel)

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleSessionDisconnect(_:)),
                       name: .muhDisconnectHostSession, object: nil)
        nc.addObserver(self, selector: #selector(handleSessionConnect(_:)),
                       name: .muhConnectHostSession, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applyTheme(_ theme: AppTheme) {
        self.theme = theme
        placeholderLabel.textColor = theme.textTertiary
    }

    @objc private func handleSessionDisconnect(_ note: Notification) {
        guard let id = note.userInfo?["hostId"] as? UUID else { return }
        disconnectedHosts.insert(id)
        destroyTerminal(hostId: id)
        refreshAfterSessionChange()
    }

    /// 「连接」：杀掉旧会话并立即拉起新会话（首次连接则直接建立）。
    @objc private func handleSessionConnect(_ note: Notification) {
        guard let id = note.userInfo?["hostId"] as? UUID else { return }
        destroyTerminal(hostId: id)
        disconnectedHosts.remove(id)
        guard let store,
              let host = store.hosts.first(where: { $0.id == id }) else { return }
        // 选中该 Host 让新终端立即可见（ssh 密码 / 首次连接提示需要用户交互），
        // 随后立即拉起新会话。
        store.select(id: id)
        let created = GhosttyTerminalView(frame: bounds)
        created.hostId = host.id
        created.command = host.defaultCommand
        terminalViews[id] = created
        refreshAfterSessionChange()
    }

    private func refreshAfterSessionChange() {
        guard let store else { return }
        update(hosts: store.hosts, selectedId: store.selectedId, interactive: interactive)
    }

    /// Kill the host's terminal session: dropping the last reference frees the
    /// ghostty surface, which closes the PTY and terminates the child (e.g. ssh).
    private func destroyTerminal(hostId: UUID) {
        guard let term = terminalViews.removeValue(forKey: hostId) else { return }
        term.removeFromSuperview()
        if visibleHostId == hostId {
            visibleHostId = nil
        }
    }

    override func layout() {
        super.layout()
        for sub in subviews where sub !== placeholderLabel {
            sub.frame = bounds
        }
        // 占位提示在终端区居中显示，避免顶部角落被忽略
        let size = placeholderLabel.intrinsicContentSize
        placeholderLabel.frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: max(size.width, 1),
            height: max(size.height, 1))
    }

    func update(hosts: [HostItem], selectedId: UUID?, interactive: Bool = true) {
        self.interactive = interactive
        placeholderLabel.stringValue = L10n.string("terminal.placeholder.disconnected")
        needsLayout = true

        let liveIds = Set(hosts.map(\.id))
        for id in terminalViews.keys.filter({ !liveIds.contains($0) }) {
            terminalViews[id]?.removeFromSuperview()
            terminalViews.removeValue(forKey: id)
            disconnectedHosts.remove(id)
        }

        // 已断开的 Host 若仍残留视图（理论不该发生），一并清掉
        for id in disconnectedHosts where terminalViews[id] != nil {
            terminalViews.removeValue(forKey: id)?.removeFromSuperview()
        }

        // 本机型（非 ssh/herdr/luvus）：点击即开终端，不保持断开态；
        // 无视图时自动拉起（含首次选中、重启后重开等场景）
        if let selectedId,
           let host = hosts.first(where: { $0.id == selectedId }),
           !host.isSessionHost {
            disconnectedHosts.remove(selectedId)
            if terminalViews[selectedId] == nil {
                let created = GhosttyTerminalView(frame: bounds)
                created.hostId = host.id
                created.command = host.defaultCommand
                terminalViews[selectedId] = created
            }
        }

        // 后台会话的视图保持挂载（隐藏），确保 PTY / 标题回传持续运行
        for view in terminalViews.values where view.superview == nil {
            view.isHidden = true
            addSubview(view)
        }

        if let selectedId,
           let term = terminalViews[selectedId],
           !disconnectedHosts.contains(selectedId) {
            visibleHostId = selectedId
            for (id, view) in terminalViews {
                view.isHidden = (id != selectedId)
            }
            term.frame = bounds
            placeholderLabel.isHidden = true
            if interactive {
                GhosttyTerminalView.makeFrontmost(term)
                focus(term)
            }
        } else {
            GhosttyTerminalView.makeFrontmost(nil)
            visibleHostId = nil
            for view in terminalViews.values {
                view.isHidden = true
            }
            placeholderLabel.isHidden = (selectedId == nil)
            window?.makeFirstResponder(nil)
        }
    }

    private func focus(_ term: GhosttyTerminalView) {
        guard let window, term.window === window, term.superview === self else { return }
        window.makeFirstResponder(term)
    }
}
