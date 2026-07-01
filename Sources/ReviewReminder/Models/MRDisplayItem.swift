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
        let interval = Date().timeIntervalSince(updatedAt)
        let hours = Int(interval / 3600)
        if hours < 24 { return "\(hours)ч" }
        let days = hours / 24
        return "\(days)д"
    }

    var isOld: Bool {
        Date().timeIntervalSince(updatedAt) > 86400 * 2
    }

    var snoozeUntilDescription: String? {
        guard status == .snoozed, let until = snoozedUntil, until > Date() else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        let cal = Calendar.current
        if cal.isDateInToday(until) {
            fmt.dateFormat = "'до' HH:mm"
        } else if cal.isDateInTomorrow(until) {
            fmt.dateFormat = "'до завтра' HH:mm"
        } else {
            fmt.dateFormat = "'до' d MMM HH:mm"
        }
        return fmt.string(from: until)
    }

    var repoName: String {
        projectPath.components(separatedBy: "/").last ?? projectPath
    }
}
