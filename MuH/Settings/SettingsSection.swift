import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case font
    case terminal
    case notifications

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .appearance:    return L10n.Settings.sectionAppearance
        case .font:          return L10n.Settings.sectionFont
        case .terminal:      return L10n.Settings.sectionTerminal
        case .notifications: return L10n.Settings.sectionNotifications
        }
    }

    var iconName: String {
        switch self {
        case .appearance:    return "paintpalette"
        case .font:          return "textformat"
        case .terminal:      return "terminal"
        case .notifications: return "bell.badge"
        }
    }
}
