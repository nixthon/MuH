import Foundation
import Observation

@Observable
final class HostTitleStore {
    private var storage: [String: String] = [:]
    private let persistenceKey: String
    private var saveWorkItem: DispatchWorkItem?

    init(persistenceKey: String = "muh.hostTitles.v1") {
        self.persistenceKey = persistenceKey
        load()
    }

    func title(for hostId: UUID) -> String? {
        storage[hostId.uuidString]
    }

    func update(hostId: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = hostId.uuidString
        guard storage[key] != trimmed else { return }
        storage[key] = trimmed
        scheduleSave()
    }

    func clear(hostId: UUID) {
        guard storage.removeValue(forKey: hostId.uuidString) != nil else { return }
        scheduleSave()
    }

    func titlesSnapshot() -> [UUID: String] {
        var out: [UUID: String] = [:]
        for (k, v) in storage {
            if let id = UUID(uuidString: k) { out[id] = v }
        }
        return out
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        storage = decoded
    }
}
