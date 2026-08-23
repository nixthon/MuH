import SwiftUI
import AppKit

struct TerminalBridge: NSViewRepresentable {
    @Bindable var store: HostStore
    var theme: AppTheme
    var interactive: Bool = true

    func makeNSView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.store = store
        view.update(hosts: store.hosts, selectedId: store.selectedId, interactive: interactive)
        return view
    }

    func updateNSView(_ view: TerminalContainerView, context: Context) {
        view.store = store
        view.update(hosts: store.hosts, selectedId: store.selectedId, interactive: interactive)
    }
}
