import AppKit
import Foundation
import UserNotifications

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
    private let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()
    private let reminderID = "com.reviewreminder.reminder"
    private var scheduledReminderFireDate: Date?
    private var firedReminderAnchor: Date?

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
        let request = UNNotificationRequest(
            identifier: "snooze-\(String(url.prefix(180)))",
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

        let request = UNNotificationRequest(
            identifier: "mr-changed-\(String(url.prefix(180)))",
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

        let request = UNNotificationRequest(
            identifier: "mr-new-\(String(url.prefix(180)))",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // anchor: timestamp the oldest pending MR became pending (not "now") — keeps the
    // fire date stable across polls instead of pushing it back on every poll tick.
    func scheduleReminder(anchor: Date, count: Int, afterMinutes: Int) async {
        let fireDate = anchor.addingTimeInterval(TimeInterval(afterMinutes * 60))

        if fireDate <= Date() {
            guard firedReminderAnchor != anchor else { return }
            firedReminderAnchor = anchor
            scheduledReminderFireDate = nil
            center.removePendingNotificationRequests(withIdentifiers: [reminderID])
            let request = UNNotificationRequest(
                identifier: reminderID,
                content: reminderContent(count: count),
                trigger: nil
            )
            try? await center.add(request)
            return
        }

        guard scheduledReminderFireDate != fireDate else { return }
        scheduledReminderFireDate = fireDate
        firedReminderAnchor = nil
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])

        // Calendar trigger (not time-interval) so it survives sleep/shutdown of the machine.
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: reminderID,
            content: reminderContent(count: count),
            trigger: trigger
        )
        try? await center.add(request)
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
        scheduledReminderFireDate = nil
        firedReminderAnchor = nil
    }
}
