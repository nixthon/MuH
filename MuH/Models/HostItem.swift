import Foundation

/// 会话型判定关键词：命令中含这些词的 host 需要显式「连接 / 断开」管理，
/// 其余（空命令本地 shell、普通命令）点击即开终端，仅提供「重启」。
private let sessionKeywords = ["ssh", "herdr", "luvus"]

/// 代表一台机器/一个独立会话环境
struct HostItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// 默认启动命令，如 "herdr" 或 "herdr --remote dev2"
    var defaultCommand: String?

    init(id: UUID = UUID(), name: String, defaultCommand: String? = nil) {
        self.id = id
        self.name = name
        self.defaultCommand = defaultCommand
    }

    /// 会话型 Host：默认命令含 ssh / herdr / luvus（大小写不敏感），
    /// 面向远程/Agent 监控会话，点击仅选中，由「连接 / 断开」显式控制生命周期。
    var isSessionHost: Bool {
        guard let cmd = defaultCommand?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cmd.isEmpty else { return false }
        let lowered = cmd.lowercased()
        return sessionKeywords.contains { lowered.contains($0) }
    }
}
