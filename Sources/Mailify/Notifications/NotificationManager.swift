import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter. Kept as its own type (was inline in
/// MailifyApp.swift's init before) so both the permission request and the
/// "new suggestions" alert live in one place.
final class NotificationManager {
    static let shared = NotificationManager()

    /// UNUserNotificationCenter.current() asserts if the process has no real
    /// bundle identifier (e.g. `swift run` / F5 debugging launches the raw
    /// .build binary rather than a packaged .app) — only call this once running
    /// from an actual app bundle.
    func requestAuthorizationIfNeeded() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }

    func notifyNewSuggestions(count: Int) {
        guard Bundle.main.bundleIdentifier != nil, count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Mailify"
        content.body = "\(count) new draft suggestion\(count == 1 ? "" : "s") ready to review"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification post error: \(error)")
            }
        }
    }

    func notifyNewCategorySuggestions(count: Int) {
        guard Bundle.main.bundleIdentifier != nil, count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Mailify"
        content.body = "\(count) new category suggestion\(count == 1 ? "" : "s") ready to review"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification post error: \(error)")
            }
        }
    }

    func notifyNewActionItems(count: Int) {
        guard Bundle.main.bundleIdentifier != nil, count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Mailify"
        content.body = "\(count) new action item\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") your attention"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification post error: \(error)")
            }
        }
    }
}
