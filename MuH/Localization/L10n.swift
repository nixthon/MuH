import Foundation

extension LocalizedStringResource {
    func withLocale(_ locale: Locale) -> LocalizedStringResource {
        var copy = self
        copy.locale = locale
        return copy
    }
}

enum L10n {
    static func string(_ key: String, _ args: CVarArg...) -> String {
        let bundle = LanguageStore.shared.effectiveBundle
        let raw = bundle.localizedString(forKey: key, value: nil, table: nil)
        return args.isEmpty ? raw : String(format: raw, arguments: args)
    }

    enum Sidebar {
        static let title                = LocalizedStringResource("sidebar.title")
        static let newWorkspace         = LocalizedStringResource("sidebar.newWorkspace")
        static let settingsTooltip      = LocalizedStringResource("sidebar.settings")
        static let deleteAlertTitle     = LocalizedStringResource("sidebar.deleteAlert.title")
        static let deleteAlertCancel    = LocalizedStringResource("sidebar.deleteAlert.cancel")
        static let deleteAlertConfirm   = LocalizedStringResource("sidebar.deleteAlert.confirm")
        static func deleteAlertMessage(_ name: String) -> LocalizedStringResource {
            LocalizedStringResource("sidebar.deleteAlert.message \(name)")
        }
        static let commandAlertTitle       = LocalizedStringResource("sidebar.row.commandPanel.editTitle")
        static let commandAlertCancel      = LocalizedStringResource("sidebar.row.commandPanel.cancel")
        static let commandAlertSave        = LocalizedStringResource("sidebar.row.commandPanel.save")
        static let commandAlertPlaceholder = LocalizedStringResource("sidebar.row.commandPanel.placeholder")
        static let showSidebar          = LocalizedStringResource("sidebar.show")
        static let hideSidebar          = LocalizedStringResource("sidebar.hide")
    }

    enum Settings {
        static let sectionAppearance    = LocalizedStringResource("settings.section.appearance")
        static let sectionFont          = LocalizedStringResource("settings.section.font")
        static let sectionTerminal      = LocalizedStringResource("settings.section.terminal")
        static let sectionNotifications = LocalizedStringResource("settings.section.notifications")

        static let close                = LocalizedStringResource("settings.close")
        static let footerEdit           = LocalizedStringResource("settings.footer.edit")
        static let footerLive           = LocalizedStringResource("settings.footer.live")

        static let theme                = LocalizedStringResource("settings.appearance.theme")
        static let backgroundOpacity    = LocalizedStringResource("settings.appearance.backgroundOpacity")
        static let backgroundBlur       = LocalizedStringResource("settings.appearance.backgroundBlur")
        static let contentOpacity       = LocalizedStringResource("settings.appearance.contentOpacity")
        static let contentShadow        = LocalizedStringResource("settings.appearance.contentShadow")
        static let windowPaddingX       = LocalizedStringResource("settings.appearance.windowPaddingX")
        static let windowPaddingY       = LocalizedStringResource("settings.appearance.windowPaddingY")
        static let cursorStyle          = LocalizedStringResource("settings.appearance.cursorStyle")
        static let cursorBlink          = LocalizedStringResource("settings.appearance.cursorBlink")
        static let unfocusedPaneOpacity = LocalizedStringResource("settings.appearance.unfocusedPaneOpacity")

        static let language             = LocalizedStringResource("settings.appearance.language")
        static let languageSystem       = LocalizedStringResource("settings.language.system")

        static let fontFamily           = LocalizedStringResource("settings.font.family")
        static let fontSize             = LocalizedStringResource("settings.font.size")
        static let fontThicken          = LocalizedStringResource("settings.font.thicken")
        static let fontDefault          = LocalizedStringResource("settings.font.default")
        static let fontCustom           = LocalizedStringResource("settings.font.custom")
        static let fontCustomPlaceholder = LocalizedStringResource("settings.font.customPlaceholder")
        static let fontListButton       = LocalizedStringResource("settings.font.listButton")

        static let resetMessage         = LocalizedStringResource("settings.reset.message")
        static let resetButton          = LocalizedStringResource("settings.reset.button")
        static let resetRowLabel        = LocalizedStringResource("settings.reset.rowLabel")
        static let resetAlertTitle      = LocalizedStringResource("settings.reset.alertTitle")
        static let resetCancel          = LocalizedStringResource("settings.reset.cancel")

        static let themeSingle          = LocalizedStringResource("settings.theme.single")
        static let themeFollowSystem    = LocalizedStringResource("settings.theme.followSystem")
        static let themeName            = LocalizedStringResource("settings.theme.name")
        static let themeLight           = LocalizedStringResource("settings.theme.light")
        static let themeDark            = LocalizedStringResource("settings.theme.dark")
        static let themeSearchPlaceholder = LocalizedStringResource("settings.theme.searchPlaceholder")
        static let themeInherit         = LocalizedStringResource("settings.theme.inherit")

        enum Terminal {
            static let scrollbackLimit        = LocalizedStringResource("settings.terminal.scrollbackLimit")
            static let copyOnSelect           = LocalizedStringResource("settings.terminal.copyOnSelect")
            static let hideMouseWhileTyping   = LocalizedStringResource("settings.terminal.hideMouseWhileTyping")
            static let confirmClose           = LocalizedStringResource("settings.terminal.confirmClose")
            static let copiedToClipboard      = LocalizedStringResource("terminal.copied.toast")
        }

        enum Notification {
            static let enableNotifications    = LocalizedStringResource("settings.notification.enable")
            static let notifyOnBlocked        = LocalizedStringResource("settings.notification.onBlocked")
            static let notifyOnCompleted      = LocalizedStringResource("settings.notification.onCompleted")
            static let enableSound            = LocalizedStringResource("settings.notification.enableSound")
            static let soundName              = LocalizedStringResource("settings.notification.soundName")
            static let playTestSound          = LocalizedStringResource("settings.notification.playTestSound")

            static let remoteSetupTitle       = LocalizedStringResource("settings.notification.remoteSetupTitle")
            static let remoteSetupDesc        = LocalizedStringResource("settings.notification.remoteSetupDesc")
            static let copyCommand            = LocalizedStringResource("settings.notification.copyCommand")
            static let copied                 = LocalizedStringResource("settings.notification.copied")
        }
    }

    enum Notification {
        static func blockedTitle(_ host: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.blocked.title \(host)")
        }
        static func completedTitle(_ host: String) -> LocalizedStringResource {
            LocalizedStringResource("notification.completed.title \(host)")
        }
    }

    enum App {
        static let ghosttyNotFoundTitle     = LocalizedStringResource("app.ghostty.notFound.title")
        static let ghosttyNotFoundDetail    = LocalizedStringResource("app.ghostty.notFound.detail")
    }

    enum Menu {
        static let settings             = LocalizedStringResource("menu.settings")
        static let editConfig           = LocalizedStringResource("menu.editConfig")
        static let newWorkspace         = LocalizedStringResource("menu.newWorkspace")
        static let cut                  = LocalizedStringResource("menu.cut")
        static let copy                 = LocalizedStringResource("menu.copy")
        static let paste                = LocalizedStringResource("menu.paste")
        static let selectAll            = LocalizedStringResource("menu.selectAll")
        static let undo                 = LocalizedStringResource("menu.undo")
        static let redo                 = LocalizedStringResource("menu.redo")
        static let help                 = LocalizedStringResource("menu.help")
        static func selectHostN(_ n: Int) -> LocalizedStringResource {
            LocalizedStringResource("menu.selectWorkspace \(n)")
        }
    }
}
