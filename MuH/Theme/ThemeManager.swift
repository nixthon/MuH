import AppKit
import Observation

enum ColorSchemePreference {
    case dark, light, system
}

@Observable
final class ThemeManager {
    private(set) var theme: AppTheme
    private var currentScheme: ColorSchemePreference = .system

    private(set) var backgroundOpacity: CGFloat = 1.0
    private(set) var backgroundBlurRadius: CGFloat = 0

    init() {
        let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let colors = GhosttyConfigReader.load(systemIsDark: isDark)
        let accent = colors.palette[3] ?? colors.palette[11] ?? colors.palette[6]
        self.theme = AppTheme.derive(
            background: colors.background,
            foreground: colors.foreground,
            accent: accent,
            systemIsDark: isDark
        )
        loadFromGhosttyConfig()
        observeSystemAppearance()
    }

    func applyScheme(_ scheme: ColorSchemePreference) {
        currentScheme = scheme
        let systemIsDark: Bool
        switch scheme {
        case .dark:
            systemIsDark = true
        case .light:
            systemIsDark = false
        case .system:
            systemIsDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }

        let colors = GhosttyConfigReader.load(systemIsDark: systemIsDark)
        let accent = colors.palette[3] ?? colors.palette[11] ?? colors.palette[6]
        self.theme = AppTheme.derive(
            background: colors.background,
            foreground: colors.foreground,
            accent: accent,
            systemIsDark: systemIsDark
        )
        loadFromGhosttyConfig()
    }

    func refresh() {
        applyScheme(currentScheme)
    }

    func loadFromGhosttyConfig() {
        let store = SettingsConfigStore()
        if let val = store.get("background-opacity"), let d = Double(val) {
            backgroundOpacity = CGFloat(max(0, min(1, d)))
        } else {
            backgroundOpacity = 1.0
        }
        if let val = store.get("background-blur-radius"), let d = Double(val) {
            backgroundBlurRadius = CGFloat(max(0, d))
        } else {
            backgroundBlurRadius = 0
        }
    }

    private func observeSystemAppearance() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.currentScheme == .system else { return }
            self.refresh()
        }
    }
}
