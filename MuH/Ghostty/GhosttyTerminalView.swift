import AppKit
import QuartzCore

/// NSView that owns a ghostty_surface_t and renders via ghostty's internal Metal renderer.
final class GhosttyTerminalView: NSView, NSTextInputClient {
    private var surface: ghostty_surface_t?
    private var displayLink: CVDisplayLink?
    private var backingObserver: NSObjectProtocol?
    private var windowKeyObserver: NSObjectProtocol?

    private var redrawBurstDeadline: Date?
    private static let burstSeconds: TimeInterval = 0.4

    // MARK: NSTextInputClient state
    private var keyTextAccumulator: String = ""
    private var insideKeyDown: Bool = false
    private let markedTextStore = NSMutableAttributedString()

    private static var registry = NSHashTable<GhosttyTerminalView>.weakObjects()
    private static weak var currentFrontmost: GhosttyTerminalView?
    private static var unfocusedOpacity: CGFloat = 1.0

    var hostId: UUID?
    var command: String?

    // MARK: - Scrollbar state
    struct ScrollbarState: Equatable {
        let total: UInt64
        let offset: UInt64
        let len: UInt64
    }

    private(set) var scrollbarState: ScrollbarState?
    private var currentCursor: NSCursor = .arrow
    private var hoveredLinkURL: String?
    private let linkTooltip = LinkHintTooltip()

    private(set) var cellSize: CGSize = .zero

    static let scrollbarDidChangeNotification = Notification.Name("GhosttyTerminalView.scrollbarDidChange")
    static let cellSizeDidChangeNotification = Notification.Name("GhosttyTerminalView.cellSizeDidChange")

    func applyScrollbar(_ s: ScrollbarState) {
        guard scrollbarState != s else { return }
        scrollbarState = s
        NotificationCenter.default.post(name: Self.scrollbarDidChangeNotification, object: self)
    }

    func applyMouseShape(_ cursor: NSCursor) {
        guard hoveredLinkURL == nil else { return }
        guard currentCursor != cursor else { return }
        currentCursor = cursor
        if let window = window, window.isKeyWindow {
            let pt = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(pt) {
                cursor.set()
            }
            window.invalidateCursorRects(for: self)
        }
    }

    static func isHoverHighlightURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme)
    }

    private func cancelGhosttyLinkHighlight() {
        guard let s = surface, let window = window, window.isKeyWindow else { return }
        let viewPt = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(viewPt) else { return }
        ghostty_surface_mouse_pos(s, -1, -1, ghostty_input_mods_e(rawValue: 0))
    }

    func applyHoveredLink(_ url: String?) {
        if let url, GhosttyTerminalView.isHoverHighlightURL(url) {
            hoveredLinkURL = url
        } else {
            if url != nil, !NSEvent.modifierFlags.contains(.command) {
                cancelGhosttyLinkHighlight()
            }
            hoveredLinkURL = nil
        }
        updateLinkAffordance()
    }

    private func updateLinkAffordance() {
        let cmdHeld = NSEvent.modifierFlags.contains(.command)
        if hoveredLinkURL != nil {
            currentCursor = cmdHeld ? .pointingHand : .arrow
            if cmdHeld {
                linkTooltip.hide()
            } else {
                linkTooltip.show("⌘ + Click to open", at: NSEvent.mouseLocation)
            }
        } else {
            currentCursor = .arrow
            linkTooltip.hide()
        }
        if let window = window, window.isKeyWindow {
            let pt = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(pt) { currentCursor.set() }
        }
    }

    func applyCellSize(backingWidth: Double, backingHeight: Double) {
        let pt = convertFromBacking(NSSize(width: backingWidth, height: backingHeight))
        let size = CGSize(width: pt.width, height: pt.height)
        guard cellSize != size else { return }
        cellSize = size
        NotificationCenter.default.post(name: Self.cellSizeDidChangeNotification, object: self)
    }

    @discardableResult
    func performBindingAction(_ action: String) -> Bool { runBindingAction(action) }

    var onFocus: (() -> Void)?
    var onUserActivity: (() -> Void)?

    private static var viewBySurface: [OpaquePointer: Weak<GhosttyTerminalView>] = [:]

    static func view(forSurface surface: ghostty_surface_t) -> GhosttyTerminalView? {
        viewBySurface[OpaquePointer(surface)]?.value
    }

    static func hasLiveSurface(hostId: UUID) -> Bool {
        registry.allObjects.contains { $0.hostId == hostId && $0.surface != nil }
    }

    static func allLiveSurfaces() -> [ghostty_surface_t] {
        registry.allObjects.compactMap { $0.surface }
    }

    static func validatedDirectory(_ path: String?) -> String? {
        guard let path else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        return path
    }

    private final class Weak<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }

    static func releaseAllExcept(_ keep: GhosttyTerminalView?) {
        let zeroMods = ghostty_input_mods_e(rawValue: 0)
        for v in registry.allObjects where v !== keep {
            guard let s = v.surface else { continue }
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, zeroMods)
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, zeroMods)
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, zeroMods)
        }
    }

    static func makeFrontmost(_ front: GhosttyTerminalView?) {
        guard currentFrontmost !== front else { return }
        currentFrontmost = front
        let zeroMods = ghostty_input_mods_e(rawValue: 0)
        GhosttyBridge.suppressClipboardWrites = true
        defer { GhosttyBridge.suppressClipboardWrites = false }
        for v in registry.allObjects {
            guard let s = v.surface else { continue }
            let isFront = (v === front)
            ghostty_surface_set_focus(s, isFront)
            ghostty_surface_set_occlusion(s, isFront)
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, zeroMods)
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, zeroMods)
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_MIDDLE, zeroMods)
            if !isFront {
                ghostty_surface_mouse_pos(s, -1, -1, zeroMods)
            }
        }
        applyUnfocusedOpacity()
    }

    static func setUnfocusedOpacity(_ value: CGFloat) {
        let clamped = max(0.0, min(1.0, value))
        guard clamped != unfocusedOpacity else { return }
        unfocusedOpacity = clamped
        applyUnfocusedOpacity()
    }

    private static func applyUnfocusedOpacity() {
        for v in registry.allObjects {
            if v === currentFrontmost || v.window == nil {
                v.alphaValue = 1.0
            } else {
                v.alphaValue = unfocusedOpacity
            }
        }
    }

    var rawSurface: ghostty_surface_t? { surface }

    override init(frame: NSRect) {
        super.init(frame: frame)
        Self.registry.add(self)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        updateTrackingAreas()
        registerForDraggedTypes([.fileURL, .string])
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach { removeTrackingArea($0) }
        let options: NSTrackingArea.Options = [
            .activeWhenFirstResponder, .mouseMoved, .cursorUpdate, .mouseEnteredAndExited, .inVisibleRect
        ]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            stopDisplayLink()
            removeBackingObserver()
            removeKeyWindowObserver()
            return
        }
        if surface == nil {
            let scale = window?.backingScaleFactor ?? 2.0
            let seed = NSHomeDirectory()
            let validated = Self.validatedDirectory(seed)
            surface = GhosttyBridge.shared.newSurface(
                nsView: self,
                scaleFactor: scale,
                workingDirectory: validated,
                command: command,
                hostId: hostId ?? UUID()
            )
            if let s = surface {
                GhosttyTerminalView.viewBySurface[OpaquePointer(s)] = Weak(self)
            }
        }
        syncSurfaceGeometry(to: bounds.size)
        if displayLink == nil {
            startDisplayLink()
        }
        installBackingObserver()
        installKeyWindowObserver()
    }

    private func installBackingObserver() {
        removeBackingObserver()
        guard let window else { return }
        backingObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.syncSurfaceGeometry(to: self.bounds.size)
        }
    }

    private func removeBackingObserver() {
        if let obs = backingObserver {
            NotificationCenter.default.removeObserver(obs)
            backingObserver = nil
        }
    }

    private func installKeyWindowObserver() {
        removeKeyWindowObserver()
        guard let window else { return }
        windowKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.clearHoverOnResignKey()
        }
    }

    private func removeKeyWindowObserver() {
        if let obs = windowKeyObserver {
            NotificationCenter.default.removeObserver(obs)
            windowKeyObserver = nil
        }
    }

    private func clearHoverOnResignKey() {
        hoveredLinkURL = nil
        linkTooltip.hide()
        currentCursor = .arrow
        if let s = surface {
            ghostty_surface_mouse_pos(s, -1, -1, ghostty_input_mods_e(rawValue: 0))
        }
    }

    private func syncSurfaceGeometry(to pointSize: NSSize) {
        guard let s = surface else { return }
        guard pointSize.width > 0, pointSize.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2.0
        let w = UInt32(pointSize.width * scale)
        let h = UInt32(pointSize.height * scale)
        guard w > 0, h > 0 else { return }
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        ghostty_surface_set_size(s, w, h)
        ghostty_surface_set_content_scale(s, scale, scale)
    }

    deinit {
        stopDisplayLink()
        removeBackingObserver()
        removeKeyWindowObserver()
        if let s = surface {
            GhosttyTerminalView.viewBySurface.removeValue(forKey: OpaquePointer(s))
            ghostty_surface_free(s)
        }
    }

    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }
        CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, ctx -> CVReturn in
            guard let ctx else { return kCVReturnSuccess }
            let view = Unmanaged<GhosttyTerminalView>.fromOpaque(ctx).takeUnretainedValue()
            let retained = Unmanaged.passRetained(view)
            DispatchQueue.main.async {
                let v = retained.takeRetainedValue()
                guard let s = v.surface else { return }
                let isFront = GhosttyTerminalView.currentFrontmost === v
                var burst = false
                if let deadline = v.redrawBurstDeadline {
                    if Date() < deadline {
                        burst = true
                    } else {
                        v.redrawBurstDeadline = nil
                        if !isFront { ghostty_surface_set_occlusion(s, false) }
                    }
                }
                guard isFront || burst else { return }
                ghostty_surface_draw(s)
            }
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(dl)
    }

    private func stopDisplayLink() {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
            self.displayLink = nil
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        syncSurfaceGeometry(to: newSize)
        if oldSize != newSize, newSize.width > 0, newSize.height > 0,
           let s = surface, Self.currentFrontmost !== self {
            ghostty_surface_set_occlusion(s, true)
            redrawBurstDeadline = Date().addingTimeInterval(Self.burstSeconds)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncSurfaceGeometry(to: bounds.size)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let s = surface { ghostty_surface_set_focus(s, true) }
        return true
    }

    override func resignFirstResponder() -> Bool {
        if hoveredLinkURL != nil { applyHoveredLink(nil) }
        if let s = surface {
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, ghostty_input_mods_e(rawValue: 0))
            _ = ghostty_surface_mouse_button(s, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, ghostty_input_mods_e(rawValue: 0))
            ghostty_surface_set_focus(s, false)
        }
        return true
    }

    @discardableResult
    private func runBindingAction(_ action: String) -> Bool {
        guard let s = surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(s, ptr, UInt(action.utf8.count))
        }
    }

    @discardableResult
    func copySelection() -> Bool { runBindingAction("copy_to_clipboard") }

    @discardableResult
    func pasteClipboard() -> Bool { runBindingAction("paste_from_clipboard") }

    @discardableResult
    func selectAllRows() -> Bool { runBindingAction("select_all") }

    var needsConfirmQuit: Bool {
        guard let surface else { return false }
        return ghostty_surface_needs_confirm_quit(surface)
    }

    @objc func paste(_ sender: Any?) { _ = pasteClipboard() }
    @objc func copy(_ sender: Any?) { _ = copySelection() }
    @objc override func selectAll(_ sender: Any?) { _ = selectAllRows() }

    override func keyDown(with event: NSEvent) {
        guard let s = surface else { super.keyDown(with: event); return }
        onUserActivity?()

        let hadMarkedTextBefore = hasMarkedText()
        insideKeyDown = true
        keyTextAccumulator = ""
        interpretKeyEvents([event])
        let committedText = keyTextAccumulator
        keyTextAccumulator = ""
        insideKeyDown = false

        if hadMarkedTextBefore && committedText.isEmpty && !hasMarkedText() {
            return
        }

        let action: ghostty_input_action_e = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        let mods = modsFromEvent(event)
        let consumedMods = consumedModsFromEvent(event)
        let keycode = UInt32(event.keyCode)
        let unshifted: UInt32 = event.characters(byApplyingModifiers: [])?
            .unicodeScalars.first?.value ?? 0
        let composing = hasMarkedText()

        func send(_ cstr: UnsafePointer<CChar>?) {
            var input = ghostty_input_key_s()
            input.action = action
            input.mods = mods
            input.consumed_mods = consumedMods
            input.keycode = keycode
            input.text = cstr
            input.unshifted_codepoint = unshifted
            input.composing = composing
            _ = ghostty_surface_key(s, input)
        }

        if !committedText.isEmpty {
            committedText.withCString { send($0) }
            postAccessibilityValueChanged()
        } else {
            send(nil)
        }
    }

    override func doCommand(by selector: Selector) {}

    override func keyUp(with event: NSEvent) {
        guard let s = surface else { return }
        var input = ghostty_input_key_s()
        input.action = GHOSTTY_ACTION_RELEASE
        input.mods = modsFromEvent(event)
        input.consumed_mods = consumedModsFromEvent(event)
        input.keycode = UInt32(event.keyCode)
        input.text = nil
        input.unshifted_codepoint = event.characters(byApplyingModifiers: [])?
            .unicodeScalars.first?.value ?? 0
        input.composing = false
        _ = ghostty_surface_key(s, input)
    }

    // MARK: - Mouse input

    override func mouseDown(with event: NSEvent) {
        onFocus?()
        onUserActivity?()
        Self.makeFrontmost(self)
        window?.makeFirstResponder(self)
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(
            s,
            GHOSTTY_MOUSE_PRESS,
            GHOSTTY_MOUSE_LEFT,
            modsFromEvent(event)
        )
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(
            s,
            GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_LEFT,
            modsFromEvent(event)
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        Self.releaseAllExcept(self)
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(
            s,
            GHOSTTY_MOUSE_PRESS,
            GHOSTTY_MOUSE_RIGHT,
            modsFromEvent(event)
        )
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(
            s,
            GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_RIGHT,
            modsFromEvent(event)
        )
    }

    override func otherMouseDown(with event: NSEvent) {
        Self.releaseAllExcept(self)
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(
            s,
            GHOSTTY_MOUSE_PRESS,
            GHOSTTY_MOUSE_MIDDLE,
            modsFromEvent(event)
        )
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
        _ = ghostty_surface_mouse_button(
            s,
            GHOSTTY_MOUSE_RELEASE,
            GHOSTTY_MOUSE_MIDDLE,
            modsFromEvent(event)
        )
    }

    override func cursorUpdate(with event: NSEvent) {
        currentCursor.set()
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateLinkAffordance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredLinkURL != nil { applyHoveredLink(nil) }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let window, window.isKeyWindow else { return }
        guard isCursorOverSelf(event) else { return }
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let s = surface else { return }
        let pt = flippedPoint(event.locationInWindow)
        ghostty_surface_mouse_pos(s, pt.x, pt.y, modsFromEvent(event))
    }

    override func scrollWheel(with event: NSEvent) {
        guard isCursorOverSelf(event) else { return }
        guard let s = surface else { return }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precision = event.hasPreciseScrollingDeltas
        if precision {
            x *= 2
            y *= 2
        }

        var mods: Int32 = 0
        if precision { mods |= 0b1 }
        let momentum: Int32
        switch event.momentumPhase {
        case .began:      momentum = 1
        case .stationary: momentum = 2
        case .changed:    momentum = 3
        case .ended:      momentum = 4
        case .cancelled:  momentum = 5
        case .mayBegin:   momentum = 6
        default:          momentum = 0
        }
        mods |= momentum << 1

        ghostty_surface_mouse_scroll(s, x, y, ghostty_input_scroll_mods_t(mods))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedDragOperation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        acceptedDragOperation(for: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let s = surface else { return false }
        let pb = sender.draggingPasteboard
        onFocus?()
        Self.makeFrontmost(self)
        window?.makeFirstResponder(self)

        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
           !urls.isEmpty {
            let joined = urls.map { Self.shellEscape($0.path) }.joined(separator: " ") + " "
            ghostty_surface_text(s, joined, UInt(joined.utf8.count))
            return true
        }

        if let text = pb.string(forType: .string), !text.isEmpty {
            ghostty_surface_text(s, text, UInt(text.utf8.count))
            return true
        }

        return false
    }

    private func acceptedDragOperation(for sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        if types.contains(.fileURL) || types.contains(.string) {
            return .copy
        }
        return []
    }

    private static let shellSafeChars: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "/._-+=@:,")
        return set
    }()

    private static func shellEscape(_ path: String) -> String {
        if path.unicodeScalars.allSatisfy({ shellSafeChars.contains($0) }) {
            return path
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    private func flippedPoint(_ windowPoint: NSPoint) -> NSPoint {
        let local = convert(windowPoint, from: nil)
        return NSPoint(x: local.x, y: bounds.height - local.y)
    }

    private func isCursorOverSelf(_ event: NSEvent) -> Bool {
        guard let win = window else { return false }
        let hit = win.contentView?.hitTest(event.locationInWindow)
        var v: NSView? = hit
        while let cur = v {
            if cur === self { return true }
            v = cur.superview
        }
        return false
    }

    private func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var rawValue: ghostty_input_mods_e.RawValue = 0
        if event.modifierFlags.contains(.shift)   { rawValue |= GHOSTTY_MODS_SHIFT.rawValue }
        if event.modifierFlags.contains(.control) { rawValue |= GHOSTTY_MODS_CTRL.rawValue }
        if event.modifierFlags.contains(.option)  { rawValue |= GHOSTTY_MODS_ALT.rawValue }
        if event.modifierFlags.contains(.command) { rawValue |= GHOSTTY_MODS_SUPER.rawValue }
        return ghostty_input_mods_e(rawValue: rawValue)
    }

    private func consumedModsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var rawValue: ghostty_input_mods_e.RawValue = 0
        if event.modifierFlags.contains(.shift)  { rawValue |= GHOSTTY_MODS_SHIFT.rawValue }
        if event.modifierFlags.contains(.option) { rawValue |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: rawValue)
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let s = string as? String {
            text = s
        } else if let a = string as? NSAttributedString {
            text = a.string
        } else {
            return
        }
        guard !text.isEmpty else { return }

        if hasMarkedText() {
            markedTextStore.mutableString.setString("")
            if let s = surface { ghostty_surface_preedit(s, nil, 0) }
        }

        if insideKeyDown {
            keyTextAccumulator.append(text)
        } else {
            guard let s = surface else { return }
            ghostty_surface_text(s, text, UInt(text.utf8.count))
            postAccessibilityValueChanged()
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let s = string as? String {
            text = s
        } else if let a = string as? NSAttributedString {
            text = a.string
        } else {
            return
        }
        markedTextStore.mutableString.setString(text)
        guard let s = surface else { return }
        if text.isEmpty {
            ghostty_surface_preedit(s, nil, 0)
        } else {
            ghostty_surface_preedit(s, text, UInt(text.utf8.count))
        }
    }

    func unmarkText() {
        markedTextStore.mutableString.setString("")
        if let s = surface { ghostty_surface_preedit(s, nil, 0) }
    }

    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange {
        let len = markedTextStore.length
        return len > 0 ? NSRange(location: 0, length: len) : NSRange(location: NSNotFound, length: 0)
    }
    func hasMarkedText() -> Bool { markedTextStore.length > 0 }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let win = window else { return .zero }
        let rectInView: NSRect
        if let surface {
            var x: Double = 0
            var y: Double = 0
            var w: Double = cellSize.width
            var h: Double = cellSize.height
            ghostty_surface_ime_point(surface, &x, &y, &w, &h)
            rectInView = NSRect(
                x: x,
                y: frame.size.height - y,
                width: w,
                height: max(h, cellSize.height)
            )
        } else {
            rectInView = NSRect(x: 0, y: 0, width: 1, height: 1)
        }
        let inWindow = convert(rectInView, to: nil)
        return win.convertToScreen(inWindow)
    }

    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }
    override func accessibilityLabel() -> String? { "Terminal" }
    override func accessibilityValue() -> Any? { "" }

    private func postAccessibilityValueChanged() {
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
}
