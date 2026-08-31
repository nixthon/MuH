import Foundation
import AppKit
import UserNotifications
import Observation

struct AgentIndicatorCounts: Equatable {
    let blocked: Int
    let done: Int
    let working: Int
    let idle: Int

    init(title: String) {
        var blocked = 0
        var done = 0
        var working = 0
        var idle = 0
        for char in title {
            switch char {
            case "×": blocked += 1
            case "✓": done += 1
            case "◐": working += 1
            case "○": idle += 1
            default: break
            }
        }
        self.blocked = blocked
        self.done = done
        self.working = working
        self.idle = idle
    }
}

enum AgentNotificationKind: Equatable {
    case blocked
    case completed
}

@Observable
final class NotificationNavigationState {
    private(set) var pendingHostId: UUID?

    func requestHostSelection(_ hostId: UUID) {
        pendingHostId = hostId
    }

    func consumeHostSelection(_ hostId: UUID) {
        guard pendingHostId == hostId else { return }
        pendingHostId = nil
    }
}

func notificationKind(
    oldTitle: String?,
    newTitle: String,
    notifyOnBlocked: Bool,
    notifyOnCompleted: Bool
) -> AgentNotificationKind? {
    let oldCounts = AgentIndicatorCounts(title: oldTitle ?? "")
    let newCounts = AgentIndicatorCounts(title: newTitle)

    if notifyOnBlocked && newCounts.blocked > oldCounts.blocked {
        return .blocked
    }

    let hasNewDone = newCounts.done > oldCounts.done
    let finishedAllWorking = oldCounts.working > 0 && newCounts.working == 0 && newCounts.blocked == 0
    if notifyOnCompleted && (hasNewDone || finishedAllWorking) {
        return .completed
    }

    return nil
}

@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()
    let navigation = NotificationNavigationState()
    private let legacyNotificationCleanupKey = "muh.notifications.clearedLegacyNavigation.v1"
    private let clickFallbackTTL: TimeInterval = 45
    private var lastDeliveredHostId: UUID?
    private var lastDeliveredAt: Date?
    private var deliveredWhileInactive = false

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
    }

    func registerCategories(on center: UNUserNotificationCenter = .current()) {
        let categories = ["AGENT_BLOCKED", "AGENT_DONE"].map {
            UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [])
        }
        center.setNotificationCategories(Set(categories))
    }

    func clearLegacyDeliveredNotificationsIfNeeded(
        on center: UNUserNotificationCenter = .current()
    ) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: legacyNotificationCleanupKey) else { return }
        center.removeAllDeliveredNotifications()
        defaults.set(true, forKey: legacyNotificationCleanupKey)
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
    func handleTitleChange(host: HostItem, oldTitle: String?, newTitle: String, isForeground: Bool = false) {
        guard enableNotifications else { return }
        guard !isForeground else { return }

        switch notificationKind(
            oldTitle: oldTitle,
            newTitle: newTitle,
            notifyOnBlocked: notifyOnBlocked,
            notifyOnCompleted: notifyOnCompleted
        ) {
        case .blocked:
            sendNotification(
                host: host,
                title: String(localized: L10n.Notification.blockedTitle(host.name)),
                body: newTitle,
                category: "AGENT_BLOCKED"
            )
        case .completed:
            sendNotification(
                host: host,
                title: String(localized: L10n.Notification.completedTitle(host.name)),
                body: newTitle,
                category: "AGENT_DONE"
            )
        case nil:
            break
        }
    }

    private func sendNotification(host: HostItem, title: String, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.userInfo = ["hostId": host.id.uuidString]
        content.threadIdentifier = "muh.host.\(host.id.uuidString)"

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
            } else {
                self.rememberDeliveredHost(host.id)
            }
        }
    }

    func sendTestNotification() {
        requestAuthorization()
        let content = UNMutableNotificationContent()
        content.title = "MuH"
        content.body = "Notification icon test"
        content.categoryIdentifier = "AGENT_DONE"

        if enableSound {
            playSound()
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "muh.test.\(Date().timeIntervalSince1970)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[MuH] Failed to deliver test notification: %@", error.localizedDescription)
            }
        }
    }

    // MARK: - Delegate Forwarding
    func handleWillPresent(
        _ notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    func handleResponse(
        _ response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let hostIdString = userInfo["hostId"] as? String,
              let hostId = UUID(uuidString: hostIdString) else {
            completionHandler()
            return
        }

        clearDeliveredClickFallback()
        routeToHost(hostId)
        completionHandler()
    }

    func consumeClickFallback() {
        onMain { [weak self] in
            guard let self else { return }
            guard let hostId = self.lastDeliveredHostId, let deliveredAt = self.lastDeliveredAt else { return }
            let age = Date().timeIntervalSince(deliveredAt)
            guard age <= self.clickFallbackTTL else {
                self.clearDeliveredClickFallback()
                return
            }
            self.clearDeliveredClickFallback()
            self.routeToHost(hostId)
        }
    }

    func consumeActivationFallback() {
        onMain { [weak self] in
            guard let self, self.deliveredWhileInactive else { return }
            self.consumeClickFallback()
        }
    }

    private func rememberDeliveredHost(_ hostId: UUID) {
        onMain { [weak self] in
            guard let self else { return }
            self.lastDeliveredHostId = hostId
            self.lastDeliveredAt = Date()
            self.deliveredWhileInactive = !NSApp.isActive
        }
    }

    private func clearDeliveredClickFallback() {
        lastDeliveredHostId = nil
        lastDeliveredAt = nil
        deliveredWhileInactive = false
    }

    private func routeToHost(_ hostId: UUID) {
        onMain {
            self.navigation.requestHostSelection(hostId)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(
                name: .muhSelectHostById,
                object: nil,
                userInfo: ["hostId": hostId]
            )
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
