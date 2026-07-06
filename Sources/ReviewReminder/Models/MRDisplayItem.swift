import Foundation

struct MRDisplayItem: Identifiable, Sendable, Equatable {
    let id: Int64
    let gitlabId: Int
    let projectPath: String
    let title: String
    let url: URL
    let author: String
    let updatedAt: Date
    let createdAt: Date
    let status: MRStatus
    let snoozedUntil: Date?
    let mrIid: Int
    let projectId: Int
    let approvalsCount: Int
    let approvalsRequired: Int
    let discussionsResolved: Int
    let discussionsTotal: Int
    let canApprove: Bool

    func taskId(pattern: String) -> String? {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: title)
        else { return nil }
        return String(title[range])
    }

    var isActive: Bool {
        switch status {
        case .pending: true
        case .snoozed: snoozedUntil.map { $0 < Date() } ?? true
        case .ignored, .approved: false
        }
    }

    var ageDescription: String {
        let interval = Date().timeIntervalSince(createdAt)
        let hours = Int(interval / 3600)
        if hours < 24 { return "\(hours)ч" }
        let days = hours / 24
        return "\(days)д"
    }

    var isOld: Bool {
        Date().timeIntervalSince(createdAt) > 86400 * 2
    }

    var snoozeUntilDescription: String? {
        guard status == .snoozed, let until = snoozedUntil, until > Date() else { return nil }
        return Self.relativeDateDescription(until, prefix: "до", tomorrowPrefix: "до завтра")
    }

    static func relativeDateDescription(_ date: Date, prefix: String, tomorrowPrefix: String) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            fmt.dateFormat = "'\(prefix)' HH:mm"
        } else if cal.isDateInTomorrow(date) {
            fmt.dateFormat = "'\(tomorrowPrefix)' HH:mm"
        } else {
            fmt.dateFormat = "'\(prefix)' d MMM HH:mm"
        }
        return fmt.string(from: date)
    }

    var repoName: String {
        projectPath.components(separatedBy: "/").last ?? projectPath
    }
}
