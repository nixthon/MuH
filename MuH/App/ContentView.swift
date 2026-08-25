import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = HostStore()
    @State private var titleStore = HostTitleStore()
    @State private var settingsStore = SettingsConfigStore()
    @State private var showSettings = false
    @State private var isFullScreen = false
    @State private var sidebarCollapsed = false
    @State private var windowLifecycle = WindowLifecycleObserver()
    @State private var sidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "muh.sidebar.width")
        return (saved >= 150 && saved <= 360) ? CGFloat(saved) : DT.Layout.sidebarWidth
    }()

    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageStore.self) private var languageStore
    @Environment(\.locale) private var locale

    var body: some View {
        _ = languageStore.tick
        let bgOpacity = isFullScreen ? 1.0 : themeManager.backgroundOpacity

        return HStack(spacing: 0) {
            if !sidebarCollapsed {
                SidebarView(
                    store: store,
                    titleStore: titleStore,
                    theme: themeManager.theme,
                    width: sidebarWidth,
                    backgroundOpacity: bgOpacity
                )
                .background(Color(themeManager.theme.sidebar).opacity(bgOpacity))
                .transition(.move(edge: .leading).combined(with: .opacity))

                SidebarResizeHandle(
                    width: $sidebarWidth,
                    theme: themeManager.theme,
                    backgroundOpacity: bgOpacity
                )
            }

            ZStack {
                TerminalBridge(
                    store: store,
                    theme: themeManager.theme,
                    interactive: !showSettings
                )
                .opacity(showSettings ? 0 : 1)
                .allowsHitTesting(!showSettings)

                if showSettings {
                    SettingsView(
                        theme: themeManager.theme,
                        settings: settingsStore,
                        onClose: { showSettings = false }
                    )
                    .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WindowDraggableArea())
        .preferredColorScheme(themeManager.theme.isDark ? .dark : .light)
        .environment(\.effectiveContentOpacity, bgOpacity)
        .muhFullSizeContent(
            backgroundOpacity: bgOpacity,
            blurRadius: themeManager.backgroundBlurRadius,
            onWindow: configureWindow
        )
        .onAppear {
            themeManager.loadFromGhosttyConfig()
            NotificationManager.shared.requestAuthorization()

            let titleStoreRef = titleStore
            let storeRef = store
            GhosttyBridge.shared.onTitleChanged = { hostId, title in
                let oldTitle = titleStoreRef.title(for: hostId)
                let suppressInitialStatus = titleStoreRef.shouldSuppressInitialStatus(
                    hostId: hostId,
                    title: title
                )
                titleStoreRef.update(hostId: hostId, title: title)
                if !suppressInitialStatus,
                   let host = storeRef.hosts.first(where: { $0.id == hostId }) {
                    let isForeground = NSApp.isActive && (storeRef.selectedId == hostId)
                    NotificationManager.shared.handleTitleChange(
                        host: host,
                        oldTitle: oldTitle,
                        newTitle: title,
                        isForeground: isForeground
                    )
                }
            }

            settingsStore.onChange = {
                GhosttyBridge.shared.reloadConfig()
                themeManager.refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .muhSelectHostById)) { note in
            if let hostId = note.userInfo?["hostId"] as? UUID {
                store.select(id: hostId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .muhOpenSettings)) { _ in
            showSettings.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .muhToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarCollapsed.toggle()
            }
        }
    }

    private func configureWindow(_ window: NSWindow) {
        GhosttyBridge.shared.applyWindowBackgroundBlur(to: window)
        windowLifecycle.attach(to: window) {
            isFullScreen = true
        } onExit: {
            isFullScreen = false
        }
    }
}

private final class WindowLifecycleObserver {
    private weak var window: NSWindow?
    private var tokens: [NSObjectProtocol] = []

    func attach(to window: NSWindow, onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        guard self.window !== window else { return }
        detach()
        self.window = window
        let center = NotificationCenter.default
        tokens = [
            center.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main
            ) { _ in onEnter() },
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { _ in onExit() }
        ]
    }

    private func detach() {
        let center = NotificationCenter.default
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }

    deinit {
        detach()
    }
}

private struct EffectiveContentOpacityKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var effectiveContentOpacity: CGFloat {
        get { self[EffectiveContentOpacityKey.self] }
        set { self[EffectiveContentOpacityKey.self] = newValue }
    }
}

extension Notification.Name {
    static let muhOpenSettings        = Notification.Name("muh.openSettings")
    static let muhToggleSidebar       = Notification.Name("muh.toggleSidebar")
    static let muhBeginCreateHost     = Notification.Name("muh.beginCreateHost")
    static let muhSelectHostAtIndex   = Notification.Name("muh.selectHostAtIndex")
    static let muhSelectHostById      = Notification.Name("muh.selectHostById")
}
