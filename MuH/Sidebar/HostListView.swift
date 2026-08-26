import AppKit

private final class FlippedRowsContainer: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastClickTime
        let pt = event.locationInWindow
        let dx = pt.x - lastClickPoint.x
        let dy = pt.y - lastClickPoint.y
        let isManualDoubleClick = dt < NSEvent.doubleClickInterval && (dx * dx + dy * dy < 25)

        if event.clickCount == 2 || isManualDoubleClick {
            lastClickTime = 0
            if let window = self.window {
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

final class HostListView: NSView {
    var onSelect: ((UUID) -> Void)?
    var onRename: ((UUID, String) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    var onRequestDelete: ((UUID) -> Void)?
    var onRequestEditCommand: ((UUID, String) -> Void)?

    private let scrollView = NSScrollView()
    private let rowsContainer = FlippedRowsContainer()
    private var theme: AppTheme = .systemFallback(isDark: true)
    private var backgroundOpacity: CGFloat = 1.0
    private var hosts: [HostItem] = []
    private var selectedId: UUID?
    private var hostTitles: [UUID: String] = [:]

    fileprivate var draggingId: UUID?
    fileprivate var previewInsertionIndex: Int?

    override var mouseDownCanMoveWindow: Bool { true }

    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = now - lastClickTime
        let pt = event.locationInWindow
        let dx = pt.x - lastClickPoint.x
        let dy = pt.y - lastClickPoint.y
        let isManualDoubleClick = dt < NSEvent.doubleClickInterval && (dx * dx + dy * dy < 25)

        if event.clickCount == 2 || isManualDoubleClick {
            lastClickTime = 0
            if let window = self.window {
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

    static let rowHeight: CGFloat = DT.Layout.rowHeight
    static let rowSpacing: CGFloat = 3
    static let outerHorizontalInset: CGFloat = DT.Space.sm

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = rowsContainer
        scrollView.autoresizingMask = []
        addSubview(scrollView)
        registerForDraggedTypes([.string])

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func contentViewBoundsDidChange() {
        syncHoverFromMouseLocation()
    }

    private func syncHoverFromMouseLocation() {
        let rows = rowsContainer.subviews.compactMap { $0 as? HostRowItemView }
        guard let window else {
            for row in rows where row.isHovered {
                row.isHovered = false
                row.updateStyle()
            }
            return
        }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        for row in rows {
            let pInRow = row.convert(mouseInWindow, from: nil)
            let shouldHover = row.bounds.contains(pInRow)
            if row.isHovered != shouldHover {
                row.isHovered = shouldHover
                row.updateStyle()
            }
        }
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutRows(animated: false)
    }

    func update(hosts: [HostItem],
                selectedId: UUID?,
                hostTitles: [UUID: String] = [:],
                theme: AppTheme,
                backgroundOpacity: CGFloat = 1.0) {
        self.hosts = hosts
        self.selectedId = selectedId
        self.hostTitles = hostTitles
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        rebuildRows()
        applyTheme(theme, backgroundOpacity: backgroundOpacity)
    }

    func applyTheme(_ theme: AppTheme, backgroundOpacity: CGFloat = 1.0) {
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        rowsContainer.subviews
            .compactMap { $0 as? HostRowItemView }
            .forEach { $0.applyTheme(theme, backgroundOpacity: backgroundOpacity) }
        needsDisplay = true
    }

    private func rebuildRows() {
        let existing = rowsContainer.subviews.compactMap { $0 as? HostRowItemView }
        let existingIds = existing.map(\.hostId)
        let targetIds = hosts.map(\.id)

        if existingIds == targetIds {
            for item in existing {
                guard let host = hosts.first(where: { $0.id == item.hostId }) else { continue }
                item.refresh(host: host,
                             isSelected: host.id == selectedId,
                             terminalTitle: hostTitles[host.id],
                             theme: theme,
                             backgroundOpacity: backgroundOpacity)
            }
            return
        }

        existing.forEach { $0.removeFromSuperview() }
        for host in hosts {
            let item = HostRowItemView(
                host: host,
                isSelected: host.id == selectedId,
                terminalTitle: hostTitles[host.id],
                theme: theme,
                backgroundOpacity: backgroundOpacity)
            wireRowCallbacks(item)
            rowsContainer.addSubview(item)
        }
        layoutRows(animated: false)
    }

    private func wireRowCallbacks(_ item: HostRowItemView) {
        let id = item.hostId
        item.onSelect = { [weak self] in self?.onSelect?(id) }
        item.onRename = { [weak self] newName in self?.onRename?(id, newName) }
        item.onRequestDelete = { [weak self] in self?.onRequestDelete?(id) }
        item.onRequestEditCommand = { [weak self] current in self?.onRequestEditCommand?(id, current) }
        item.onDragEnded = { [weak self] in self?.cleanupAfterDrag() }
    }

    fileprivate func cleanupAfterDrag() {
        guard draggingId != nil || previewInsertionIndex != nil else { return }
        draggingId = nil
        previewInsertionIndex = nil
        rowsContainer.subviews
            .compactMap { $0 as? HostRowItemView }
            .forEach { $0.isDragGhost = false }
        layoutRows(animated: true)
    }

    private func previewOrdered(items: [HostRowItemView]) -> [HostRowItemView] {
        guard let draggingId,
              let insertion = previewInsertionIndex,
              let fromIdx = items.firstIndex(where: { $0.hostId == draggingId })
        else { return items }

        var copy = items
        let picked = copy.remove(at: fromIdx)
        let dest = insertion > fromIdx ? insertion - 1 : insertion
        copy.insert(picked, at: max(0, min(copy.count, dest)))
        return copy
    }

    private func insertionIndex(forY y: CGFloat, items: [HostRowItemView]) -> Int {
        guard !items.isEmpty else { return 0 }
        for (i, row) in items.enumerated() {
            if y < row.frame.midY { return i }
        }
        return items.count
    }

    private func layoutRows(animated: Bool) {
        let rawItems = rowsContainer.subviews.compactMap { $0 as? HostRowItemView }
        let items = previewOrdered(items: rawItems)
        guard !items.isEmpty else {
            rowsContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 0)
            return
        }

        let width = max(0, bounds.width - Self.outerHorizontalInset * 2)
        var y: CGFloat = 0
        var targetFrames: [(HostRowItemView, NSRect)] = []

        for item in items {
            let rowH = item.preferredHeight(forWidth: width)
            let frame = NSRect(x: Self.outerHorizontalInset, y: y, width: width, height: rowH)
            targetFrames.append((item, frame))
            y += rowH + Self.rowSpacing
        }

        let totalH = max(bounds.height, y - Self.rowSpacing)
        rowsContainer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: totalH)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                for (item, frame) in targetFrames {
                    item.animator().frame = frame
                }
            }
        } else {
            for (item, frame) in targetFrames {
                item.frame = frame
            }
        }
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let idStr = sender.draggingPasteboard.string(forType: .string),
              let id = UUID(uuidString: idStr),
              hosts.contains(where: { $0.id == id })
        else { return [] }

        draggingId = id
        if let row = rowsContainer.subviews.compactMap({ $0 as? HostRowItemView }).first(where: { $0.hostId == id }) {
            row.isDragGhost = true
        }
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggingId != nil else { return [] }
        let pointInDoc = rowsContainer.convert(sender.draggingLocation, from: nil)
        let items = rowsContainer.subviews.compactMap { $0 as? HostRowItemView }
        let newInsertion = insertionIndex(forY: pointInDoc.y, items: items)
        if newInsertion != previewInsertionIndex {
            previewInsertionIndex = newInsertion
            layoutRows(animated: true)
        }
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        cleanupAfterDrag()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let draggingId,
              let fromIdx = hosts.firstIndex(where: { $0.id == draggingId })
        else {
            cleanupAfterDrag()
            return false
        }
        let finalInsertion = previewInsertionIndex ?? fromIdx
        let targetIdx = finalInsertion > fromIdx ? finalInsertion - 1 : finalInsertion

        cleanupAfterDrag()
        if fromIdx != targetIdx {
            onReorder?(fromIdx, targetIdx)
        }
        return true
    }
}

// MARK: - HostRowItemView

private final class HostRowItemView: NSView, NSTextFieldDelegate, NSDraggingSource {
    let hostId: UUID

    var onSelect: (() -> Void)?
    var onRename: ((String) -> Void)?
    var onRequestDelete: (() -> Void)?
    var onRequestEditCommand: ((String) -> Void)?
    var onDragEnded: (() -> Void)?

    var isDragGhost: Bool = false {
        didSet {
            guard oldValue != isDragGhost else { return }
            alphaValue = isDragGhost ? 0.35 : 1
        }
    }

    private let backgroundLayerView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    fileprivate let renameField = NSTextField()

    fileprivate var isSelected: Bool
    fileprivate var isHovered = false
    fileprivate var isRenaming = false
    fileprivate var theme: AppTheme
    fileprivate var backgroundOpacity: CGFloat
    private var host: HostItem
    private var terminalTitle: String?
    fileprivate var originalTitle: String = ""

    init(host: HostItem, isSelected: Bool,
         terminalTitle: String? = nil,
         theme: AppTheme,
         backgroundOpacity: CGFloat = 1.0) {
        self.hostId = host.id
        self.host = host
        self.isSelected = isSelected
        self.terminalTitle = terminalTitle
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        super.init(frame: .zero)
        setup()
        updateStyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true

        backgroundLayerView.wantsLayer = true
        backgroundLayerView.layer?.cornerRadius = DT.Radius.row
        backgroundLayerView.layer?.masksToBounds = true
        addSubview(backgroundLayerView)

        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.isBezeled = false
        subtitleLabel.drawsBackground = false
        subtitleLabel.isEditable = false
        subtitleLabel.isSelectable = false
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = DT.Font.mono
        addSubview(subtitleLabel)

        renameField.isBezeled = false
        renameField.drawsBackground = false
        renameField.isEditable = true
        renameField.isSelectable = true
        renameField.focusRingType = .none
        renameField.isHidden = true
        renameField.delegate = self
        renameField.font = DT.Font.bodyBold
        addSubview(renameField)
    }

    override func layout() {
        super.layout()
        backgroundLayerView.frame = bounds

        let hPad = DT.Space.md
        let topPad = DT.Space.xs
        let titleH = ceil(titleLabel.intrinsicContentSize.height)

        let titleFrame = NSRect(
            x: hPad,
            y: bounds.height - topPad - titleH,
            width: bounds.width - hPad * 2,
            height: titleH)
        titleLabel.frame = titleFrame
        renameField.frame = titleFrame

        if !subtitleLabel.isHidden {
            let subH = ceil(subtitleLabel.intrinsicContentSize.height)
            subtitleLabel.frame = NSRect(
                x: hPad,
                y: max(topPad, titleFrame.minY - DT.Space.xs - subH),
                width: bounds.width - hPad * 2,
                height: subH)
        }
    }

    fileprivate func preferredHeight(forWidth width: CGFloat) -> CGFloat {
        return HostListView.rowHeight
    }

    func refresh(host: HostItem, isSelected: Bool,
                 terminalTitle: String? = nil,
                 theme: AppTheme,
                 backgroundOpacity: CGFloat = 1.0) {
        self.host = host
        self.isSelected = isSelected
        self.terminalTitle = terminalTitle
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        if !isRenaming, titleLabel.stringValue != host.name {
            titleLabel.stringValue = host.name
        }
        updateStyle()
        needsLayout = true
    }

    func applyTheme(_ theme: AppTheme, backgroundOpacity: CGFloat = 1.0) {
        self.theme = theme
        self.backgroundOpacity = backgroundOpacity
        updateStyle()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateStyle()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        guard !isRenaming else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    fileprivate var mouseDownLocation: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        if event.clickCount == 2 {
            beginRenameAction()
            return
        }
        onSelect?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let renameItem = NSMenuItem(
            title: L10n.string("sidebar.row.rename"),
            action: #selector(beginRenameAction),
            keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        let commandItem = NSMenuItem(
            title: L10n.string("sidebar.row.commandPanel.editTitle"),
            action: #selector(requestEditCommandAction),
            keyEquivalent: "")
        commandItem.target = self
        menu.addItem(commandItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: L10n.string("sidebar.row.delete"),
            action: #selector(deleteAction),
            keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc fileprivate func deleteAction() {
        onRequestDelete?()
    }

    @objc private func requestEditCommandAction() {
        onRequestEditCommand?(host.defaultCommand ?? "")
    }

    @objc fileprivate func beginRenameAction() {
        guard !isRenaming else { return }
        originalTitle = titleLabel.stringValue
        renameField.stringValue = originalTitle
        titleLabel.isHidden = true
        renameField.isHidden = false
        isRenaming = true
        window?.makeFirstResponder(renameField)
        renameField.currentEditor()?.selectAll(nil)
        window?.invalidateCursorRects(for: self)
    }

    private func finishRenameUI() {
        renameField.isHidden = true
        titleLabel.isHidden = false
        isRenaming = false
        window?.invalidateCursorRects(for: self)
    }

    fileprivate func commitRename() {
        guard isRenaming else { return }
        let newTitle = renameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finishRenameUI()
        if !newTitle.isEmpty && newTitle != host.name {
            titleLabel.stringValue = newTitle
            onRename?(newTitle)
        }
    }

    fileprivate func cancelRename() {
        guard isRenaming else { return }
        renameField.stringValue = originalTitle
        finishRenameUI()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelRename()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        commitRename()
    }

    override func mouseDragged(with event: NSEvent) {
        if isRenaming { return }
        let dx = event.locationInWindow.x - mouseDownLocation.x
        let dy = event.locationInWindow.y - mouseDownLocation.y
        guard (dx * dx + dy * dy) > 16 else { return }

        let pbItem = NSPasteboardItem()
        pbItem.setString(hostId.uuidString, forType: .string)

        let ghost = snapshotForDragging()
        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        draggingItem.setDraggingFrame(bounds, contents: ghost)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func snapshotForDragging() -> NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage() }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?()
    }

    private func renderAttributedStatusTitle(_ title: String, theme: AppTheme) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let symbolFont = NSFont(name: "Menlo", size: 10.5) ?? DT.Font.mono
        let textFont = DT.Font.small

        for char in title {
            let color: NSColor
            let isSymbol: Bool
            switch char {
            case "×":
                color = theme.danger                  // 🔴 阻塞 / 需要确认
                isSymbol = true
            case "✓", "○":
                color = theme.success                 // 🟢 完成 (✓) / 存活空闲待命 (○)
                isSymbol = true
            case "●", "◐":
                color = theme.accent                  // 🟡 正在执行 (working)
                isSymbol = true
            case "·":
                color = theme.textTertiary.withAlphaComponent(0.6) // 未知状态点
                isSymbol = true
            default:
                color = theme.textTertiary            // 灰色文本 (如 "dev2: idle")
                isSymbol = false
            }

            var attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: isSymbol ? symbolFont : textFont
            ]
            if isSymbol {
                // 增加字间距，让各 Agent 状态标志不再紧贴在一起
                attrs[.kern] = 3.0
            }
            result.append(NSAttributedString(string: String(char), attributes: attrs))
        }
        return result
    }

    private func updateContent() {
        titleLabel.stringValue = host.name

        let rawTitle = terminalTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title = rawTitle, !title.isEmpty {
            subtitleLabel.attributedStringValue = renderAttributedStatusTitle(title, theme: theme)
            subtitleLabel.isHidden = false
            self.toolTip = "\(host.name)\n\(title)"
        } else if let cmd = host.defaultCommand, !cmd.isEmpty {
            subtitleLabel.attributedStringValue = NSAttributedString(
                string: "$ \(cmd)",
                attributes: [.foregroundColor: theme.textTertiary, .font: DT.Font.mono]
            )
            subtitleLabel.isHidden = false
            self.toolTip = "\(host.name)\n$ \(cmd)"
        } else {
            subtitleLabel.attributedStringValue = NSAttributedString(string: "")
            subtitleLabel.isHidden = true
            self.toolTip = host.name
        }
    }

    fileprivate func updateStyle() {
        if isSelected {
            backgroundLayerView.layer?.backgroundColor = theme.border.withAlphaComponent(backgroundOpacity).cgColor
            titleLabel.textColor = theme.textPrimary
            titleLabel.font = DT.Font.bodyBold
        } else if isHovered {
            backgroundLayerView.layer?.backgroundColor = theme.border.withAlphaComponent(backgroundOpacity).cgColor
            titleLabel.textColor = theme.textSecondary
            titleLabel.font = DT.Font.bodyBold
        } else {
            backgroundLayerView.layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = theme.textSecondary
            titleLabel.font = DT.Font.bodyBold
        }

        renameField.textColor = theme.textPrimary
        updateContent()
        needsDisplay = true
    }
}
