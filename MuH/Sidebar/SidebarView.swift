import SwiftUI
import AppKit

struct SidebarView: View {
    @Bindable var store: HostStore
    @Bindable var titleStore: HostTitleStore
    var theme: AppTheme
    var width: CGFloat = DT.Layout.sidebarWidth
    var backgroundOpacity: CGFloat = 1.0
    @Environment(LanguageStore.self) private var languageStore
    @Environment(\.locale) private var locale

    @State private var hostToDelete: UUID?
    @State private var hostToEditCommand: (id: UUID, current: String)?
    @State private var editingCommandText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarListBridge(
                store: store,
                hostTitles: titleStore.titlesSnapshot(),
                theme: theme,
                languageTick: languageStore.tick,
                backgroundOpacity: backgroundOpacity,
                onRequestDelete: { hostToDelete = $0 },
                onRequestEditCommand: { id, current in
                    hostToEditCommand = (id, current)
                    editingCommandText = current
                }
            )
            .padding(.top, DT.Layout.trafficLightTopInset)

            footer
        }
        .frame(width: width)
        .onReceive(NotificationCenter.default.publisher(for: .muhBeginCreateHost)) { _ in
            createHostWithDefaultName()
        }
        .onReceive(NotificationCenter.default.publisher(for: .muhSelectHostAtIndex)) { note in
            guard let idx = note.userInfo?["index"] as? Int,
                  idx >= 0, idx < store.hosts.count else { return }
            store.select(id: store.hosts[idx].id)
        }
        .alert(String(localized: (L10n.Sidebar.deleteAlertTitle).withLocale(locale)),
               isPresented: Binding(
                   get: { hostToDelete != nil },
                   set: { if !$0 { hostToDelete = nil } })) {
            Button(String(localized: (L10n.Sidebar.deleteAlertCancel).withLocale(locale)), role: .cancel) {
                hostToDelete = nil
            }
            Button(String(localized: (L10n.Sidebar.deleteAlertConfirm).withLocale(locale)), role: .destructive) {
                if let id = hostToDelete {
                    titleStore.clear(hostId: id)
                    store.deleteHost(id: id)
                }
                hostToDelete = nil
            }
        } message: {
            if let id = hostToDelete, let h = store.hosts.first(where: { $0.id == id }) {
                Text(L10n.Sidebar.deleteAlertMessage(h.name))
            }
        }
        .alert(
            String(localized: (L10n.Sidebar.commandAlertTitle).withLocale(locale)),
            isPresented: Binding(
                get: { hostToEditCommand != nil },
                set: { if !$0 { hostToEditCommand = nil } }
            )
        ) {
            TextField(
                String(localized: (L10n.Sidebar.commandAlertPlaceholder).withLocale(locale)),
                text: $editingCommandText
            )
            Button(String(localized: (L10n.Sidebar.commandAlertSave).withLocale(locale))) {
                if let host = hostToEditCommand {
                    store.updateDefaultCommand(hostId: host.id, command: editingCommandText)
                }
                hostToEditCommand = nil
            }
            Button(String(localized: (L10n.Sidebar.commandAlertCancel).withLocale(locale)), role: .cancel) {
                hostToEditCommand = nil
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DT.Space.xs) {
            IconButton(
                theme: theme,
                help: String(localized: L10n.Sidebar.settingsTooltip.withLocale(locale)),
                size: 24,
                cornerRadius: DT.Radius.sm
            ) {
                NotificationCenter.default.post(name: .muhOpenSettings, object: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(theme.textSecondary))
            }

            Spacer()

            IconButton(
                theme: theme,
                help: String(localized: L10n.Sidebar.newWorkspace.withLocale(locale)),
                size: 24,
                cornerRadius: DT.Radius.sm
            ) {
                NotificationCenter.default.post(name: .muhBeginCreateHost, object: nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color(theme.textSecondary))
            }
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
    }

    private func createHostWithDefaultName() {
        let baseName = "~"
        var candidate = baseName
        var counter = 2
        let existing = Set(store.hosts.map(\.name))
        while existing.contains(candidate) {
            candidate = "\(baseName) \(counter)"
            counter += 1
        }
        store.createHost(name: candidate, defaultCommand: nil)
    }
}
