import SwiftUI
import AppKit

struct SettingsTabBarView: View {
    let theme: AppTheme
    @Binding var selection: SettingsSection
    let onClose: () -> Void

    @Environment(\.effectiveContentOpacity) private var effectiveContentOpacity
    @Environment(\.locale) private var locale

    var body: some View {
        let opacity = effectiveContentOpacity
        return HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DT.Radius.strip, style: .continuous)
                    .fill(Color(theme.sidebar.withAlphaComponent(opacity)))

                HStack(spacing: DT.Layout.pillInset) {
                    ForEach(SettingsSection.allCases) { section in
                        pill(for: section)
                    }
                }
                .padding(.horizontal, DT.Layout.pillInset)
            }
            .frame(maxWidth: .infinity)

            IconButton(theme: theme, help: String(localized: (L10n.Settings.close).withLocale(locale)), action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color(theme.textSecondary))
            }
            .frame(width: 28)
        }
        .frame(height: DT.Layout.tabHeight)
    }

    private func pill(for section: SettingsSection) -> some View {
        let isSelected = selection == section
        let pillHeight = DT.Layout.tabHeight - 2 * DT.Layout.pillInset
        return Button {
            selection = section
        } label: {
            Text(section.label)
                .font(Font(DT.Font.small))
                .foregroundColor(Color(isSelected ? theme.textPrimary : theme.textSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(maxWidth: .infinity,
                       minHeight: pillHeight,
                       maxHeight: pillHeight,
                       alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.pill, style: .continuous)
                        .fill(Color(isSelected ? theme.canvas.withAlphaComponent(effectiveContentOpacity) : .clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: DT.Layout.tabItemWidth)
        .onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
