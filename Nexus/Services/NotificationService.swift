import Foundation
import UserNotifications

// MARK: - Notification Service
//
// Posts a native macOS notification when a session drops unexpectedly or fails,
// so an engineer who tabbed away still learns a switch went offline. Respects the
// `notifyOnDisconnect` setting and system Do-Not-Disturb (UNUserNotificationCenter
// is delivered through Notification Center). User-initiated tab closes do NOT
// notify (see ConnectionSession.isClosing).

final class NotificationService {
    static let shared = NotificationService()

    /// Mirrors AppSettings.notifyOnDisconnect.
    var enabled: Bool = true

    private var requested = false

    /// True only when running inside a real app bundle. Calling
    /// UNUserNotificationCenter from a bare command-line process traps, so guard it.
    private var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorizationIfNeeded() {
        guard hasBundle, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a disconnect/failure notification for a session.
    func sessionDropped(name: String, failed: Bool, reason: String?) {
        guard enabled, hasBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = name
        if failed {
            content.body = reason?.isEmpty == false ? reason! : String(localized: "notify.failed.body")
        } else {
            content.body = String(localized: "notify.disconnected.body")
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
