import Foundation
import Observation

func isAgentStatusTitle(_ title: String) -> Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased().hasSuffix(": idle") {
        return true
    }

    let symbols: Set<Character> = ["×", "✓", "◐", "○", "·"]
    return trimmed.contains { symbols.contains($0) }
}

/// 存储各 Host 终端的当前标题(即 Agent 状态生命体征)。
///
/// 标题是 PTY 会话的实时状态,只在本会话内有意义;App 重启后所有
/// SSH/Herdr 会话都是全新的,旧标题与新会话毫无对应关系,跨启动持久化
/// 必然导致侧边栏显示"未知时刻"的过期状态。因此这里只保留内存态:
/// 重启后所有机器默认 unknown,直到对应终端重连并推来本会话第一条标题。
@Observable
final class HostTitleStore {
    private var storage: [String: String] = [:]
    private var statusBaselineHosts = Set<UUID>()

    init() {
        // 清理历史版本遗留在 UserDefaults 中的跨启动标题缓存
        UserDefaults.standard.removeObject(forKey: "muh.hostTitles.v1")
    }

    func title(for hostId: UUID) -> String? {
        storage[hostId.uuidString]
    }

    /// Returns true once per app session for the first Herdr status title.
    /// Reattached sessions use their current state as the new baseline.
    func shouldSuppressInitialStatus(hostId: UUID, title: String) -> Bool {
        guard isAgentStatusTitle(title) else { return false }
        return statusBaselineHosts.insert(hostId).inserted
    }

    func update(hostId: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = hostId.uuidString
        guard storage[key] != trimmed else { return }
        storage[key] = trimmed
    }

    func clear(hostId: UUID) {
        statusBaselineHosts.remove(hostId)
        storage.removeValue(forKey: hostId.uuidString)
    }

    func titlesSnapshot() -> [UUID: String] {
        var out: [UUID: String] = [:]
        for (k, v) in storage {
            if let id = UUID(uuidString: k) { out[id] = v }
        }
        return out
    }
}
