import SwiftUI
import AppKit

@main
struct MuHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var themeManager = ThemeManager()
    @State private var languageStore = LanguageStore.shared

    init() {
        Self.migrateLegacyUserDefaultsIfNeeded()
        NSWindow.allowsAutomaticWindowTabbing = false
        if !Self.isRunningTests {
            let ok = GhosttyBridge.shared.initialize()
            if !ok { print("[MuH] Warning: libghostty initialization failed") }
        }
    }

    private static func migrateLegacyUserDefaultsIfNeeded() {
        let current = UserDefaults.standard
        if current.object(forKey: "muh.hosts.items") == nil,
           let legacy = UserDefaults(suiteName: "com.herdr.MuH") {
            let dict = legacy.dictionaryRepresentation()
            for (key, value) in dict where key.hasPrefix("muh.") {
                current.set(value, forKey: key)
            }
        }
    }

    private static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
    }

    var body: some Scene {
        _ = languageStore.tick

        return WindowGroup {
            if GhosttyBridge.shared.isInitialized {
                ContentView()
                    .environment(themeManager)
                    .environment(languageStore)
                    .environment(\.locale, languageStore.locale)
            } else {
                GhosttyMissingView()
                    .environment(languageStore)
                    .environment(\.locale, languageStore.locale)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(String(localized: L10n.Menu.settings.withLocale(LanguageStore.shared.locale))) {
                    post(.muhOpenSettings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            strippedDefaultCommands

            CommandGroup(replacing: .undoRedo) {
                Button(String(localized: L10n.Menu.undo.withLocale(LanguageStore.shared.locale))) {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: .command)

                Button(String(localized: L10n.Menu.redo.withLocale(LanguageStore.shared.locale))) {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .pasteboard) {
                Button(String(localized: L10n.Menu.cut.withLocale(LanguageStore.shared.locale))) {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: .command)

                Button(String(localized: L10n.Menu.copy.withLocale(LanguageStore.shared.locale))) {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c", modifiers: .command)

                Button(String(localized: L10n.Menu.paste.withLocale(LanguageStore.shared.locale))) {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v", modifiers: .command)

                Button(String(localized: L10n.Menu.selectAll.withLocale(LanguageStore.shared.locale))) {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a", modifiers: .command)
            }

            hostCommands
        }
    }

    @CommandsBuilder private var strippedDefaultCommands: some Commands {
        CommandGroup(replacing: .systemServices)    { EmptyView() }
        CommandGroup(replacing: .saveItem)          { EmptyView() }
        CommandGroup(replacing: .textEditing)       { EmptyView() }
        CommandGroup(replacing: .textFormatting)    { EmptyView() }
        CommandGroup(replacing: .toolbar)           { EmptyView() }
        CommandGroup(replacing: .windowArrangement) { EmptyView() }
        CommandGroup(replacing: .help) {
            Button(String(localized: L10n.Menu.help.withLocale(LanguageStore.shared.locale))) {}.disabled(true)
        }
    }

    @CommandsBuilder private var hostCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            ForEach(1...9, id: \.self) { idx in
                Button(String(localized: L10n.Menu.selectHostN(idx).withLocale(LanguageStore.shared.locale))) {
                    NotificationCenter.default.post(
                        name: .muhSelectHostAtIndex,
                        object: nil,
                        userInfo: ["index": idx - 1])
                }
                .keyboardShortcut(KeyEquivalent(Character(String(idx))), modifiers: .command)
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesMenu = nil
        guard let mainMenu = NSApp.mainMenu else { return }
        let topLevelMenusToRemove: Set<String> = [
            "Format", "View", "格式", "显示", "视图"
        ]
        mainMenu.items.removeAll { topLevelMenusToRemove.contains($0.title) }

        if let appMenu = mainMenu.items.first?.submenu {
            let serviceTitles: Set<String> = ["Services", "服务"]
            appMenu.items.removeAll { serviceTitles.contains($0.title) || $0.submenu == NSApp.servicesMenu }
        }
    }
}

struct GhosttyMissingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text(L10n.App.ghosttyNotFoundTitle)
                .font(.title2.bold())
            Text(L10n.App.ghosttyNotFoundDetail)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(width: 400, height: 280)
    }
}
