import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = HostStore()
    @State private var titleStore = HostTitleStore()
    @State private var settingsStore = SettingsConfigStore()
    @State private var showSettings = false
    @State private var isFullScreen = false
    @State private var sidebarCollapsed = false
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
        let contentBg = isFullScreen ? 1.0 : themeManager.contentEffectiveOpacity

        return HStack(spacing: 0) {
            if !sidebarCollapsed {
                SidebarView(
                    store: store,
                    titleStore: titleStore,
                    theme: themeManager.theme,
                    width: sidebarWidth,
                    backgroundOpacity: bgOpacity
                )
                .transition(.move(edge: .leading).combined(with: .opacity))

                SidebarResizeHandle(
                    width: $sidebarWidth,
                    theme: themeManager.theme
                )
            }

            ZStack {
                TerminalBridge(
                    store: store,
                    theme: themeManager.theme,
                    backgroundOpacity: contentBg,
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
            .background(Color(themeManager.theme.canvas).opacity(contentBg))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .strokeBorder(
                        Color(themeManager.theme.border).opacity(0.4),
                        lineWidth: DT.Stroke.hairline
                    )
            }
            .shadow(
                color: Color.black.opacity(0.15),
                radius: 8,
                x: 0,
                y: 2
            )
            .padding(.top, DT.Space.xs)
            .padding(.trailing, DT.Space.xs)
            .padding(.bottom, DT.Space.xs)
            .padding(.leading, sidebarCollapsed ? DT.Space.xs : 0)
        }
        .background(Color(themeManager.theme.sidebar).opacity(bgOpacity))
        .preferredColorScheme(themeManager.theme.isDark ? .dark : .light)
        .environment(\.effectiveContentOpacity, contentBg)
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
                titleStoreRef.update(hostId: hostId, title: title)
                if let host = storeRef.hosts.first(where: { $0.id == hostId }) {
                    NotificationManager.shared.handleTitleChange(host: host, oldTitle: oldTitle, newTitle: title)
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

        NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { _ in isFullScreen = true }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { _ in isFullScreen = false }
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
