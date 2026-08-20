import Foundation
import Observation

@Observable
final class HostStore {
    private(set) var hosts: [HostItem] = []
    var selectedId: UUID?

    var selectedHost: HostItem? {
        hosts.first(where: { $0.id == selectedId })
    }

    private let persistenceKey: String
    private var saveWorkItem: DispatchWorkItem?

    init(persistenceKey: String = "muh.hosts.v1") {
        self.persistenceKey = persistenceKey
        load()
        if hosts.isEmpty {
            let defaultLocal = HostItem(name: "~", defaultCommand: "herdr")
            hosts = [defaultLocal]
            selectedId = defaultLocal.id
            save()
        } else if selectedId == nil || !hosts.contains(where: { $0.id == selectedId }) {
            selectedId = hosts.first?.id
        }
    }

    func select(id: UUID) {
        guard hosts.contains(where: { $0.id == id }) else { return }
        selectedId = id
    }

    @discardableResult
    func createHost(name: String, defaultCommand: String? = nil) -> HostItem {
        let host = HostItem(name: name, defaultCommand: defaultCommand)
        hosts.append(host)
        selectedId = host.id
        scheduleSave()
        return host
    }

    func renameHost(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[idx].name = trimmed
        save()
    }

    func updateDefaultCommand(hostId: UUID, command: String) {
        guard let idx = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        hosts[idx].defaultCommand = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func moveHost(from source: IndexSet, to destination: Int) {
        hosts.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func deleteHost(id: UUID) {
        guard let idx = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts.remove(at: idx)
        if selectedId == id {
            selectedId = hosts.first?.id
        }
        save()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode([HostItem].self, from: data)
        else { return }
        self.hosts = decoded
    }
}
