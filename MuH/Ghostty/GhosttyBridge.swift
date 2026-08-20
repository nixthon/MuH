import Foundation
import AppKit

final class GhosttyBridge {
    static let shared = GhosttyBridge()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private(set) var isInitialized = false

    var onPwdChanged: ((UUID, String) -> Void)?
    var onTitleChanged: ((UUID, String) -> Void)?

    static var suppressClipboardWrites = false

    private init() {}

    @discardableResult
    func initialize() -> Bool {
        let argc = CommandLine.argc
        let rawArgv = CommandLine.unsafeArgv
        guard ghostty_init(UInt(argc), rawArgv) == 0 else {
            print("[GhosttyBridge] ghostty_init failed")
            return false
        }

        exportEnvVars()

        guard let cfg = buildConfig() else {
            print("[GhosttyBridge] buildConfig failed")
            return false
        }
        self.config = cfg

        var rtConfig = ghostty_runtime_config_s()
        rtConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        rtConfig.supports_selection_clipboard = false
        rtConfig.wakeup_cb = GhosttyBridge.wakeupCallback
        rtConfig.action_cb = GhosttyBridge.actionCallback
        rtConfig.close_surface_cb = GhosttyBridge.closeSurfaceCallback
        rtConfig.read_clipboard_cb = GhosttyBridge.readClipboardCallback
        rtConfig.confirm_read_clipboard_cb = GhosttyBridge.confirmReadClipboardCallback
        rtConfig.write_clipboard_cb = GhosttyBridge.writeClipboardCallback

        guard let appHandle = ghostty_app_new(&rtConfig, cfg) else {
            print("[GhosttyBridge] ghostty_app_new failed")
            return false
        }
        self.app = appHandle
        self.isInitialized = true
        return true
    }

    func teardown() {
        if let a = app { ghostty_app_free(a) }
        if let c = config { ghostty_config_free(c) }
        app = nil
        config = nil
        isInitialized = false
    }

    private func buildConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        ghostty_config_load_default_files(cfg)

        let cacheDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/MuH")
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        let muhDefaultsPath = (cacheDir as NSString).appendingPathComponent("muh-defaults.conf")
        let muhDefaults = """
        window-padding-x = 4
        window-padding-y = 4
        cursor-style-blink = false
        """
        try? muhDefaults.write(toFile: muhDefaultsPath, atomically: true, encoding: .utf8)
        muhDefaultsPath.withCString { ghostty_config_load_file(cfg, $0) }

        ghostty_config_load_recursive_files(cfg)

        if let resourcesPath = Bundle.main.resourcePath {
            let ghosttyDir = (resourcesPath as NSString).appendingPathComponent("ghostty")
            if FileManager.default.fileExists(atPath: ghosttyDir) {
                let cacheDir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Caches/MuH")
                try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
                let tmpResourcesConf = (cacheDir as NSString).appendingPathComponent("resources-dir.conf")
                let line = "resources-dir = \"\(ghosttyDir)\"\n"
                try? line.write(toFile: tmpResourcesConf, atomically: true, encoding: .utf8)
                tmpResourcesConf.withCString { ghostty_config_load_file(cfg, $0) }
            }
        }

        if let themePath = GhosttyConfigReader.resolvedThemePath() {
            themePath.withCString { ghostty_config_load_file(cfg, $0) }
        }

        let muhOverridePath = SettingsConfigStore.defaultPath
        if FileManager.default.fileExists(atPath: muhOverridePath) {
            muhOverridePath.withCString { ghostty_config_load_file(cfg, $0) }
        }

        ghostty_config_finalize(cfg)
        return cfg
    }

    func reloadConfig() {
        guard isInitialized, let appHandle = app else { return }
        guard let newCfg = buildConfig() else { return }
        ghostty_app_update_config(appHandle, newCfg)
        for surface in GhosttyTerminalView.allLiveSurfaces() {
            ghostty_surface_update_config(surface, newCfg)
        }
        if let old = config { ghostty_config_free(old) }
        self.config = newCfg
    }

    private static let envLock = NSLock()

    func newSurface(nsView: NSView,
                    scaleFactor: Double,
                    workingDirectory: String?,
                    command: String?,
                    hostId: UUID) -> ghostty_surface_t? {
        guard isInitialized, let appHandle = app else { return nil }
        Self.envLock.lock()
        defer { Self.envLock.unlock() }

        setenv("MUH_HOST_ID", hostId.uuidString, 1)
        let resolvedWorkingDirectory = workingDirectory ?? NSHomeDirectory()
        let initialInput: String?
        if let cmd = command?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            initialInput = cmd.hasSuffix("\n") ? cmd : "\(cmd)\n"
        } else {
            initialInput = nil
        }

        var surfCfg = ghostty_surface_config_new()
        surfCfg.scale_factor = scaleFactor
        surfCfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfCfg.platform.macos.nsview = Unmanaged.passUnretained(nsView).toOpaque()
        surfCfg.userdata = Unmanaged.passUnretained(nsView).toOpaque()

        return resolvedWorkingDirectory.withCString { wdPtr in
            surfCfg.working_directory = wdPtr
            guard let input = initialInput else {
                return ghostty_surface_new(appHandle, &surfCfg)
            }
            return input.withCString { inputPtr in
                surfCfg.initial_input = inputPtr
                return ghostty_surface_new(appHandle, &surfCfg)
            }
        }
    }

    func applyWindowBackgroundBlur(to window: NSWindow) {
        guard let appHandle = app else { return }
        let ptr = Unmanaged.passUnretained(window).toOpaque()
        ghostty_set_window_background_blur(appHandle, ptr)
    }

    func applyColorScheme(_ isDark: Bool) {
        guard let appHandle = app else { return }
        let scheme: ghostty_color_scheme_e = isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
        ghostty_app_set_color_scheme(appHandle, scheme)
    }

    private func exportEnvVars() {
        setenv("MUH", "1", 1)
        setenv("TERM_PROGRAM", "ghostty", 0)
        setenv("COLORTERM", "truecolor", 0)
    }

    // MARK: - C Callbacks

    private static let wakeupCallback: ghostty_runtime_wakeup_cb = { userdata in
        guard let ptr = userdata else { return }
        let bridge = Unmanaged<GhosttyBridge>.fromOpaque(ptr).takeUnretainedValue()
        DispatchQueue.main.async {
            guard let a = bridge.app else { return }
            ghostty_app_tick(a)
        }
    }

    private static let closeSurfaceCallback: ghostty_runtime_close_surface_cb = { _, _ in }

    private static let readClipboardCallback: ghostty_runtime_read_clipboard_cb = { userdata, _, state in
        guard let userdata else { return false }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = view.rawSurface else { return false }
        guard let str = NSPasteboard.general.string(forType: .string), !str.isEmpty else { return false }
        str.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
        }
        return true
    }

    private static let confirmReadClipboardCallback: ghostty_runtime_confirm_read_clipboard_cb = { _, _, _, _ in }

    private static let writeClipboardCallback: ghostty_runtime_write_clipboard_cb = { _, _, content, count, _ in
        guard !GhosttyBridge.suppressClipboardWrites else { return }
        guard let content = content, count > 0 else { return }

        var items: [(NSPasteboard.PasteboardType, String)] = []
        for i in 0..<count {
            let item = content[i]
            guard let dataPtr = item.data,
                  let str = String(cString: dataPtr, encoding: .utf8) else { continue }
            let mime: String = item.mime.flatMap { String(cString: $0, encoding: .utf8) } ?? "text/plain"
            let type: NSPasteboard.PasteboardType
            switch mime {
            case "text/plain": type = .string
            case "text/html":  type = .html
            default:           type = NSPasteboard.PasteboardType(mime)
            }
            items.append((type, str))
        }
        guard !items.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        for (type, str) in items {
            pb.setString(str, forType: type)
        }
    }

    private static let actionCallback: ghostty_runtime_action_cb = { _, target, action in
        switch action.tag {
        case GHOSTTY_ACTION_CONFIG_CHANGE:
            return true
        case GHOSTTY_ACTION_CELL_SIZE:
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else { return true }
            let cs = action.action.cell_size
            let w = Double(cs.width)
            let h = Double(cs.height)
            DispatchQueue.main.async {
                GhosttyTerminalView.view(forSurface: surface)?.applyCellSize(backingWidth: w, backingHeight: h)
            }
            return true
        case GHOSTTY_ACTION_SCROLLBAR:
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else { return true }
            let sb = action.action.scrollbar
            let state = GhosttyTerminalView.ScrollbarState(total: sb.total, offset: sb.offset, len: sb.len)
            DispatchQueue.main.async {
                GhosttyTerminalView.view(forSurface: surface)?.applyScrollbar(state)
            }
            return true
        case GHOSTTY_ACTION_PWD:
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface, let cstr = action.action.pwd.pwd else { return true }
            let raw = String(cString: cstr)
            DispatchQueue.main.async {
                guard let view = GhosttyTerminalView.view(forSurface: surface), let hostId = view.hostId else { return }
                let pwd = sanitizedPwd(raw) ?? raw
                GhosttyBridge.shared.onPwdChanged?(hostId, pwd)
            }
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            let ou = action.action.open_url
            guard let ptr = ou.url else { return true }
            let data = Data(bytes: UnsafeRawPointer(ptr), count: Int(ou.len))
            guard let raw = String(data: data, encoding: .utf8) else { return true }
            DispatchQueue.main.async {
                if let url = GhosttyBridge.resolveOpenURL(raw) {
                    NSWorkspace.shared.open(url)
                }
            }
            return true
        case GHOSTTY_ACTION_MOUSE_SHAPE:
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else { return true }
            let shape = action.action.mouse_shape
            let cursor: NSCursor
            switch shape {
            case GHOSTTY_MOUSE_SHAPE_DEFAULT:
                cursor = .arrow
            case GHOSTTY_MOUSE_SHAPE_TEXT:
                cursor = .iBeam
            case GHOSTTY_MOUSE_SHAPE_POINTER:
                cursor = .pointingHand
            case GHOSTTY_MOUSE_SHAPE_COL_RESIZE,
                 GHOSTTY_MOUSE_SHAPE_EW_RESIZE,
                 GHOSTTY_MOUSE_SHAPE_E_RESIZE,
                 GHOSTTY_MOUSE_SHAPE_W_RESIZE:
                cursor = .resizeLeftRight
            case GHOSTTY_MOUSE_SHAPE_ROW_RESIZE,
                 GHOSTTY_MOUSE_SHAPE_NS_RESIZE,
                 GHOSTTY_MOUSE_SHAPE_N_RESIZE,
                 GHOSTTY_MOUSE_SHAPE_S_RESIZE:
                cursor = .resizeUpDown
            case GHOSTTY_MOUSE_SHAPE_MOVE,
                 GHOSTTY_MOUSE_SHAPE_ALL_SCROLL:
                cursor = .openHand
            case GHOSTTY_MOUSE_SHAPE_GRABBING:
                cursor = .closedHand
            case GHOSTTY_MOUSE_SHAPE_CROSSHAIR,
                 GHOSTTY_MOUSE_SHAPE_CELL:
                cursor = .crosshair
            case GHOSTTY_MOUSE_SHAPE_NOT_ALLOWED,
                 GHOSTTY_MOUSE_SHAPE_NO_DROP:
                cursor = .operationNotAllowed
            default:
                cursor = .arrow
            }
            DispatchQueue.main.async {
                GhosttyTerminalView.view(forSurface: surface)?.applyMouseShape(cursor)
            }
            return true
        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface else { return true }
            let mol = action.action.mouse_over_link
            let url: String?
            if let ptr = mol.url, mol.len > 0 {
                url = String(data: Data(bytes: UnsafeRawPointer(ptr), count: Int(mol.len)), encoding: .utf8)
            } else {
                url = nil
            }
            DispatchQueue.main.async {
                GhosttyTerminalView.view(forSurface: surface)?.applyHoveredLink(url)
            }
            return true
        case GHOSTTY_ACTION_SET_TITLE, GHOSTTY_ACTION_SET_WINDOW_TITLE, GHOSTTY_ACTION_SET_TAB_TITLE:
            guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface, let cstr = action.action.set_title.title else { return true }
            let title = String(cString: cstr)
            DispatchQueue.main.async {
                guard let view = GhosttyTerminalView.view(forSurface: surface), let hostId = view.hostId else { return }
                GhosttyBridge.shared.onTitleChanged?(hostId, title)
            }
            return true
        case GHOSTTY_ACTION_RING_BELL:
            // 拦截终端底层原始蜂鸣，避免与 MuH NotificationManager 的高语义提醒音重复叠加发声
            return true
        default:
            return false
        }
    }

    static func resolveOpenURL(_ raw: String) -> URL? {
        let allowed: Set<String> = ["http", "https", "mailto", "file"]
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              allowed.contains(scheme)
        else { return nil }
        if scheme == "file", url.path.isEmpty { return nil }
        return url
    }

    private static func sanitizedPwd(_ raw: String) -> String? {
        for scheme in ["kitty-shell-cwd://", "file://"] {
            guard raw.hasPrefix(scheme) else { continue }
            let afterScheme = raw.dropFirst(scheme.count)
            if let slash = afterScheme.firstIndex(of: "/") {
                return String(afterScheme[slash...])
            }
            return "/"
        }
        return nil
    }
}
