import Foundation

/// 代表一台机器/一个独立会话环境
struct HostItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// 默认启动命令，如 "herdr" 或 "herdr --remote dev2"
    var defaultCommand: String?

    init(id: UUID = UUID(), name: String, defaultCommand: String? = "herdr") {
        self.id = id
        self.name = name
        self.defaultCommand = defaultCommand
    }
}
