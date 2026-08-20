import SwiftUI
import AppKit

struct SidebarListBridge: NSViewRepresentable {
    @Bindable var store: HostStore
    var hostTitles: [UUID: String] = [:]
    var theme: AppTheme
    var languageTick: Int
    var backgroundOpacity: CGFloat = 1.0
    var onRequestDelete: (UUID) -> Void
    var onRequestEditCommand: (UUID, String) -> Void

    func makeNSView(context: Context) -> HostListView {
        let view = HostListView()
        wire(view)
        view.update(hosts: store.hosts,
                    selectedId: store.selectedId,
                    hostTitles: hostTitles,
                    theme: theme,
                    backgroundOpacity: backgroundOpacity)
        return view
    }

    func updateNSView(_ view: HostListView, context: Context) {
        _ = languageTick
        wire(view)
        view.update(hosts: store.hosts,
                    selectedId: store.selectedId,
                    hostTitles: hostTitles,
                    theme: theme,
                    backgroundOpacity: backgroundOpacity)
    }

    private func wire(_ view: HostListView) {
        view.onSelect = { id in store.select(id: id) }
        view.onRename = { id, name in store.renameHost(id: id, to: name) }
        view.onReorder = { from, to in store.moveHost(from: IndexSet([from]), to: to) }
        view.onRequestDelete = { id in onRequestDelete(id) }
        view.onRequestEditCommand = { id, current in onRequestEditCommand(id, current) }
    }
}
