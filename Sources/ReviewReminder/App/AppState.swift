import Foundation
import Observation
import ServiceManagement

@Observable
@MainActor
final class AppState: @unchecked Sendable {
    var mergeRequests: [MRDisplayItem] = []
    var pendingCount: Int = 0
    var isLoading: Bool = false
    var lastError: String?
    var actionError: String?
    var currentUser: GitLabUser?
    var stats: ReviewStats?
    var nextReminderDate: Date?

    nonisolated let keychain      = KeychainService()
    nonisolated let apiClient     = GitLabAPIClient()
    nonisolated let storage       = StorageService()
    nonisolated let notifications = NotificationService()
    private let polling = PollingService()
    private var didSetup = false

    func setup() {
        guard !didSetup else { return }
        didSetup = true
        Task {
            try? await storage.setup()
            await notifications.requestAuthorization()
            await polling.start(appState: self)
        }
        // Local tick every 15s: handles snooze expiry and reminder firing without depending on
        // the network poll cycle, so both stay accurate regardless of pollIntervalMinutes.
        Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self else { return }
                self.activateExpiredSnoozes()
                await self.tickReminder()
            }
        }
    }

    private func tickReminder() async {
        let config = AppConfig.load()
        guard config.reminderEnabled, pendingCount > 0 else {
            await notifications.cancelReminder()
            nextReminderDate = nil
            return
        }
        await notifications.scheduleReminder(count: pendingCount, afterMinutes: config.reminderIntervalMinutes)
        nextReminderDate = await notifications.nextFireDate(afterMinutes: config.reminderIntervalMinutes)
    }

    func refreshNow() {
        Task { await polling.pollNow() }
    }

    func refreshStats() {
        Task {
            let s = try? await storage.fetchStats()
            self.stats = s
        }
    }

    // MARK: - MR Actions

    func recordViewed(id: Int64) {
        Task {
            let already = (try? await storage.hasEvent(.reviewed, mrId: id)) ?? false
            guard !already else { return }
            let item = mergeRequests.first(where: { $0.id == id })
            try? await storage.recordEvent(.init(
                id: nil, mrId: id, eventType: .reviewed, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: item?.title ?? "", url: item?.url.absoluteString)
            ))
        }
    }

    func snoozeMR(id: Int64, minutes: Int) {
        Task {
            let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let state = MRUserStateRecord(mrId: id, status: .snoozed, snoozedUntil: until, updatedAt: Date())
            let item = mergeRequests.first(where: { $0.id == id })
            try? await storage.upsertUserState(state)
            try? await storage.recordEvent(.init(
                id: nil, mrId: id, eventType: .snoozed, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: item?.title ?? "", url: item?.url.absoluteString)
            ))
            updateItemStatus(id: id, status: .snoozed, snoozedUntil: until)
            if AppConfig.load().systemNotificationsEnabled, let item {
                await notifications.scheduleSnoozeExpired(
                    mrTitle: item.title,
                    url: item.url.absoluteString,
                    afterSeconds: TimeInterval(minutes * 60)
                )
            }
        }
    }

    func ignoreMR(id: Int64) {
        Task {
            let state = MRUserStateRecord(mrId: id, status: .ignored, snoozedUntil: nil, updatedAt: Date())
            let item = mergeRequests.first(where: { $0.id == id })
            try? await storage.upsertUserState(state)
            try? await storage.recordEvent(.init(
                id: nil, mrId: id, eventType: .ignored, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: item?.title ?? "", url: item?.url.absoluteString)
            ))
            updateItemStatus(id: id, status: .ignored, snoozedUntil: nil)
        }
    }

    func approveMR(item: MRDisplayItem) {
        Task {
            do {
                try await apiClient.approveMR(projectId: item.projectId, mrIid: item.mrIid)
            } catch {
                actionError = "Не удалось одобрить «\(item.title)»: \(error.localizedDescription)"
                return
            }
            let state = MRUserStateRecord(mrId: item.id, status: .approved, snoozedUntil: nil, updatedAt: Date())
            try? await storage.upsertUserState(state)
            try? await storage.recordEvent(.init(
                id: nil, mrId: item.id, eventType: .approved, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: item.title, url: item.url.absoluteString, mrIid: item.mrIid, projectPath: item.projectPath)
            ))
            updateItemStatus(id: item.id, status: .approved, snoozedUntil: nil)
        }
    }

    func dismissIgnore(id: Int64) {
        Task {
            let state = MRUserStateRecord(mrId: id, status: .pending, snoozedUntil: nil, updatedAt: Date())
            let item = mergeRequests.first(where: { $0.id == id })
            try? await storage.upsertUserState(state)
            try? await storage.recordEvent(.init(
                id: nil, mrId: id, eventType: .dismissed, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: item?.title ?? "", url: item?.url.absoluteString)
            ))
            updateItemStatus(id: id, status: .pending, snoozedUntil: nil)
        }
    }

    func undoReviewed(id: Int64) {
        Task {
            let state = MRUserStateRecord(mrId: id, status: .pending, snoozedUntil: nil, updatedAt: Date())
            let item = mergeRequests.first(where: { $0.id == id })
            try? await storage.upsertUserState(state)
            try? await storage.recordEvent(.init(
                id: nil, mrId: id, eventType: .dismissed, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: item?.title ?? "", url: item?.url.absoluteString)
            ))
            updateItemStatus(id: id, status: .pending, snoozedUntil: nil)
        }
    }

    func resetStats() {
        Task {
            try? await storage.deleteAllEvents()
            stats = nil
            refreshStats()
        }
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            var config = AppConfig.load()
            config.launchAtLogin = enabled
            config.save()
        } catch {
            lastError = "Launch at login: \(error.localizedDescription)"
        }
    }

    // MARK: - Private

    func activateExpiredSnoozes() {
        let now = Date()
        var changed = false
        for i in mergeRequests.indices {
            let item = mergeRequests[i]
            guard item.status == .snoozed,
                  let until = item.snoozedUntil,
                  until <= now else { continue }
            mergeRequests[i] = MRDisplayItem(
                id: item.id, gitlabId: item.gitlabId, projectPath: item.projectPath,
                title: item.title, url: item.url, author: item.author,
                updatedAt: item.updatedAt, createdAt: item.createdAt,
                status: .pending, snoozedUntil: nil,
                mrIid: item.mrIid, projectId: item.projectId,
                approvalsCount: item.approvalsCount, approvalsRequired: item.approvalsRequired,
                discussionsResolved: item.discussionsResolved, discussionsTotal: item.discussionsTotal,
                canApprove: item.canApprove
            )
            changed = true
        }
        if changed {
            pendingCount = mergeRequests.filter(\.isActive).count
        }
    }

    func updateItemStatus(id: Int64, status: MRStatus, snoozedUntil: Date?) {
        if let idx = mergeRequests.firstIndex(where: { $0.id == id }) {
            let old = mergeRequests[idx]
            mergeRequests[idx] = MRDisplayItem(
                id: old.id, gitlabId: old.gitlabId, projectPath: old.projectPath,
                title: old.title, url: old.url, author: old.author,
                updatedAt: old.updatedAt, createdAt: old.createdAt,
                status: status, snoozedUntil: snoozedUntil,
                mrIid: old.mrIid, projectId: old.projectId,
                approvalsCount: old.approvalsCount,
                approvalsRequired: old.approvalsRequired,
                discussionsResolved: old.discussionsResolved,
                discussionsTotal: old.discussionsTotal,
                canApprove: old.canApprove
            )
        }
        pendingCount = mergeRequests.filter(\.isActive).count
    }
}
