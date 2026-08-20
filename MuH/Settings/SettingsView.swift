import SwiftUI

struct SettingsView: View {
    let theme: AppTheme
    let settings: SettingsConfigStore
    let onClose: () -> Void

    @Environment(\.locale) private var locale
    @Environment(\.effectiveContentOpacity) private var effectiveContentOpacity
    @State private var section: SettingsSection = .appearance

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBarView(
                theme: theme,
                selection: $section,
                onClose: onClose
            )
            .padding(.all, DT.Space.xs)

            VStack(spacing: 0) {
                sectionBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.strip, style: .continuous))
            .padding(.horizontal, DT.Space.xs)
            .padding(.bottom, DT.Space.xs)
        }
        .background(Color(theme.canvas.withAlphaComponent(effectiveContentOpacity)))
        .tint(Color(theme.accent))
        .onReceive(NotificationCenter.default.publisher(for: .muhOpenSettings)) { _ in
            section = .appearance
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .appearance:    AppearanceSectionView(theme: theme, settings: settings)
        case .font:          FontSectionView(theme: theme, settings: settings)
        case .terminal:      TerminalSectionView(theme: theme, settings: settings)
        case .notifications: NotificationSectionView(theme: theme)
        }
    }

    private var footer: some View {
        HStack {
            TextLinkButton(theme: theme, title: String(localized: (L10n.Settings.footerEdit).withLocale(locale))) {
                settings.openInEditor()
            }
            Spacer()
            Text(L10n.Settings.footerLive)
                .font(Font(DT.Font.small))
                .foregroundColor(Color(theme.textTertiary))
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .background(Color(theme.canvas.withAlphaComponent(effectiveContentOpacity)))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(theme.border.withAlphaComponent(0.5 * effectiveContentOpacity)))
                .frame(height: DT.Stroke.hairline)
        }
    }
}
