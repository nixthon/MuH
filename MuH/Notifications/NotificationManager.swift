import Foundation
import AppKit
import UserNotifications
import Observation

@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // MARK: - Available System Sounds
    static let systemSounds: [String] = [
        "Basso",
        "Blow",
        "Bottle",
        "Frog",
        "Funk",
        "Glass",
        "Hero",
        "Morse",
        "Ping",
        "Pop",
        "Purr",
        "Sosumi",
        "Submarine",
        "Tink"
    ]

    // MARK: - Settings Properties (Stored in UserDefaults)
    var enableNotifications: Bool {
        didSet { UserDefaults.standard.set(enableNotifications, forKey: "muh.notifications.enabled") }
    }

    var notifyOnBlocked: Bool {
        didSet { UserDefaults.standard.set(notifyOnBlocked, forKey: "muh.notifications.onBlocked") }
    }

    var notifyOnCompleted: Bool {
        didSet { UserDefaults.standard.set(notifyOnCompleted, forKey: "muh.notifications.onCompleted") }
    }

    var enableSound: Bool {
        didSet { UserDefaults.standard.set(enableSound, forKey: "muh.notifications.soundEnabled") }
    }

    var soundName: String {
        didSet { UserDefaults.standard.set(soundName, forKey: "muh.notifications.soundName") }
    }

    override private init() {
        let defaults = UserDefaults.standard
        self.enableNotifications = defaults.object(forKey: "muh.notifications.enabled") as? Bool ?? true
        self.notifyOnBlocked = defaults.object(forKey: "muh.notifications.onBlocked") as? Bool ?? true
        self.notifyOnCompleted = defaults.object(forKey: "muh.notifications.onCompleted") as? Bool ?? true
        self.enableSound = defaults.object(forKey: "muh.notifications.soundEnabled") as? Bool ?? true
        self.soundName = defaults.string(forKey: "muh.notifications.soundName") ?? "Glass"

        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                NSLog("[MuH] Notification permission error: %@", error.localizedDescription)
            }
        }
    }

    func playSound(name: String? = nil) {
        let soundToPlay = name ?? soundName
        if let sound = NSSound(named: soundToPlay) {
            sound.play()
        }
    }

    // MARK: - State Inspection & Notification Dispatch
    private struct IndicatorCounts {
        let blocked: Int   // ×
        let done: Int      // ✓
        let working: Int   // ◐
        let idle: Int      // ○

        init(from title: String) {
            var b = 0, d = 0, w = 0, i = 0
            for char in title {
                switch char {
                case "×": b += 1
                case "✓": d += 1
                case "◐": w += 1
                case "○": i += 1
                default: break
                }
            }
            self.blocked = b
            self.done = d
            self.working = w
            self.idle = i
        }
    }

    func handleTitleChange(host: HostItem, oldTitle: String?, newTitle: String) {
        guard enableNotifications else { return }

        let oldCounts = IndicatorCounts(from: oldTitle ?? "")
        let newCounts = IndicatorCounts(from: newTitle)

        // 1. 检查是否有新增的阻塞 (×)
        if notifyOnBlocked && newCounts.blocked > oldCounts.blocked {
            sendNotification(
                host: host,
                title: String(localized: L10n.Notification.blockedTitle(host.name)),
                body: newTitle,
                category: "AGENT_BLOCKED"
            )
            return
        }

        // 2. 检查是否有完成任务 (✓)
        // 条件：新增了 ✓，或者从正在执行 (◐ > 0) 变成全部执行完 (◐ == 0 && ✓ > 0)
        let hasNewDone = newCounts.done > oldCounts.done
        let finishedAll = oldCounts.working > 0 && newCounts.working == 0 && newCounts.done > 0

        if notifyOnCompleted && (hasNewDone || finishedAll) {
            sendNotification(
                host: host,
                title: String(localized: L10n.Notification.completedTitle(host.name)),
                body: newTitle,
                category: "AGENT_DONE"
            )
            return
        }
    }

    private func sendNotification(host: HostItem, title: String, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = ["hostId": host.id.uuidString]

        if enableSound {
            playSound()
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "muh.agent.\(host.id.uuidString).\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[MuH] Failed to deliver notification: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        guard let hostIdString = userInfo["hostId"] as? String,
              let hostId = UUID(uuidString: hostIdString) else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: .muhSelectHostById,
                object: nil,
                userInfo: ["hostId": hostId]
            )
        }
    }
}
