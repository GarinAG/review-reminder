import Foundation

enum MRFilterMode: String, CaseIterable, Sendable {
    case allWithoutMyReview = "all_without_my_review"
    case assignedToMe       = "assigned_to_me"

    var label: String {
        switch self {
        case .allWithoutMyReview: "Все МРы без моего ревью"
        case .assignedToMe:       "Только назначенные мне"
        }
    }
}

struct AppConfig: Sendable {
    var gitlabURL: String           = ""
    var repositories: [String]      = []
    var pollIntervalMinutes: Int     = 5
    var reminderEnabled: Bool        = true
    var reminderIntervalMinutes: Int = 60
    var systemNotificationsEnabled: Bool = true
    var mrFilter: MRFilterMode       = .allWithoutMyReview
    var excludeDrafts: Bool          = true
    var launchAtLogin: Bool          = false
    var taskTrackerEnabled: Bool     = false
    var taskTrackerBaseURL: String   = "https://tracker.yandex.ru/"
    var taskTrackerPattern: String   = #"^([A-Z]+-\d+):"#
    var ignoredLabels: [String]      = []

    static func load() -> AppConfig {
        let d = UserDefaults.standard
        var c = AppConfig()
        c.gitlabURL           = d.string(forKey: "gitlabURL") ?? ""
        c.repositories        = d.stringArray(forKey: "repositories") ?? []
        c.pollIntervalMinutes = d.integer(forKey: "pollIntervalMinutes").nonZero ?? 5
        c.reminderEnabled     = d.object(forKey: "reminderEnabled") as? Bool ?? true
        c.reminderIntervalMinutes = d.integer(forKey: "reminderIntervalMinutes").nonZero ?? 60
        c.systemNotificationsEnabled = d.object(forKey: "systemNotificationsEnabled") as? Bool ?? true
        c.mrFilter            = MRFilterMode(rawValue: d.string(forKey: "mrFilter") ?? "") ?? .allWithoutMyReview
        c.excludeDrafts       = d.object(forKey: "excludeDrafts") as? Bool ?? true
        c.launchAtLogin       = d.object(forKey: "launchAtLogin") as? Bool ?? false
        c.taskTrackerEnabled  = d.object(forKey: "taskTrackerEnabled") as? Bool ?? false
        c.taskTrackerBaseURL  = d.string(forKey: "taskTrackerBaseURL") ?? "https://tracker.yandex.ru/"
        c.ignoredLabels       = d.stringArray(forKey: "ignoredLabels") ?? []
        c.taskTrackerPattern  = d.string(forKey: "taskTrackerPattern") ?? #"^([A-Z]+-\d+):"#
        return c
    }

    func save() {
        let d = UserDefaults.standard
        d.set(gitlabURL,                    forKey: "gitlabURL")
        d.set(repositories,                 forKey: "repositories")
        d.set(pollIntervalMinutes,          forKey: "pollIntervalMinutes")
        d.set(reminderEnabled,              forKey: "reminderEnabled")
        d.set(reminderIntervalMinutes,      forKey: "reminderIntervalMinutes")
        d.set(systemNotificationsEnabled,   forKey: "systemNotificationsEnabled")
        d.set(mrFilter.rawValue,            forKey: "mrFilter")
        d.set(excludeDrafts,                forKey: "excludeDrafts")
        d.set(launchAtLogin,                forKey: "launchAtLogin")
        d.set(taskTrackerEnabled,           forKey: "taskTrackerEnabled")
        d.set(taskTrackerBaseURL,           forKey: "taskTrackerBaseURL")
        d.set(ignoredLabels,                 forKey: "ignoredLabels")
        d.set(taskTrackerPattern,            forKey: "taskTrackerPattern")
    }

    var isConfigured: Bool {
        !gitlabURL.isEmpty && !repositories.isEmpty
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
