import BoardProtocol
import Foundation
@preconcurrency import UserNotifications

enum FocusCompletionReceipt {
    static let defaultsKey = "ilo-board.last-focus-completion-event.v1"

    static func shouldNotify(eventID: String, defaults: UserDefaults) -> Bool {
        guard defaults.string(forKey: defaultsKey) != eventID else { return false }
        defaults.set(eventID, forKey: defaultsKey)
        return true
    }
}

enum FocusCompletionNotifier {
    static func prepare() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func post(_ completion: FocusCompletionMessage) {
        let content = UNMutableNotificationContent()
        content.title = "Focus session complete"
        content.body = "Your (completion.durationMinutes)-minute ILO Board focus block is done."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: completion.eventID,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
