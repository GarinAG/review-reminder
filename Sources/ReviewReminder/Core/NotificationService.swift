import AppKit
import Foundation
@preconcurrency import UserNotifications

// Shows notifications even while app is active (always-running menu bar app)
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let urlString = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: urlString),
           url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
}

actor NotificationService {
    private nonisolated(unsafe) let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()
    private let reminderID = "com.reviewreminder.reminder"
    private var lastFiredAt: Date?

    func requestAuthorization() async {
        center.delegate = delegate
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        // Clear any pending notifications from old bundle ID
        center.removeAllPendingNotificationRequests()
    }

    func scheduleSnoozeExpired(mrTitle: String, url: String, afterSeconds: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = "Время ревью"
        content.body = mrTitle
        content.sound = .default
        content.userInfo = ["url": url]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, afterSeconds), repeats: false)
        let id = "snooze-\(String(url.prefix(180)))"
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func notifyMRChanged(title: String, url: String) async {
        let content = UNMutableNotificationContent()
        content.title = "МР обновлён — требуется ревью"
        content.body = title
        content.sound = .default
        content.userInfo = ["url": url]

        let id = "mr-changed-\(String(url.prefix(180)))"
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func notifyNewMR(title: String, url: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Новый МР — требуется ревью"
        content.body = title
        content.sound = .default
        content.userInfo = ["url": url]

        let id = "mr-new-\(String(url.prefix(180)))"
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // Repeats every `afterMinutes` from the last fire (baseline is "now" on first observation
    // since app start / last cancelReminder()), for as long as there is at least one pending MR.
    // Driven by a local tick (see AppState) rather than the network poll cycle, so it fires
    // reliably regardless of poll interval.
    func scheduleReminder(count: Int, afterMinutes: Int) async {
        // First observation since app start / last cancelReminder(): establish baseline "now"
        // instead of firing immediately for MRs already stale in GitLab — avoids double-firing
        // alongside the "new MR" notification.
        guard let base = lastFiredAt else {
            lastFiredAt = Date()
            return
        }

        let fireDate = base.addingTimeInterval(TimeInterval(afterMinutes * 60))
        guard fireDate <= Date() else { return }

        let request = UNNotificationRequest(
            identifier: reminderID,
            content: reminderContent(count: count),
            trigger: nil
        )
        do {
            try await center.add(request)
            lastFiredAt = Date()
        } catch {
            // Delivery failed (e.g. permission revoked) — keep base so we retry next tick.
        }
    }

    private func reminderContent(count: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Review Reminder"
        content.body = "\(count) МР\(count == 1 ? "" : "а") ожидают вашего ревью"
        content.sound = .default
        return content
    }

    func notifyMention(mrTitle: String, author: String, url: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Вас упомянули в МР"
        content.body = "@\(author): \(mrTitle)"
        content.sound = .default
        content.userInfo = ["url": url]

        let request = UNNotificationRequest(
            identifier: "mention-\(String(url.prefix(150)))-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func cancelReminder() async {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        lastFiredAt = nil
    }

    // Projected next fire time for UI display.
    func nextFireDate(afterMinutes: Int) -> Date? {
        guard let lastFiredAt else { return nil }
        return lastFiredAt.addingTimeInterval(TimeInterval(afterMinutes * 60))
    }
}
