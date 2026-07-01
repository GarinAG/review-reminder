import Foundation

actor PollingService {
    private weak var appState: AppState?
    private var isRunning = false

    func start(appState: AppState) {
        self.appState = appState
        isRunning = true
        Task { await runLoop() }
    }

    func stop() {
        isRunning = false
    }

    func pollNow() async {
        await poll()
    }

    // MARK: - Private

    private func runLoop() async {
        while isRunning {
            await poll()
            let config = AppConfig.load()
            let interval = config.pollIntervalMinutes
            try? await Task.sleep(nanoseconds: UInt64(interval) * 60 * 1_000_000_000)
        }
    }

    private func poll() async {
        guard let appState else { return }

        let config = AppConfig.load()
        guard config.isConfigured else { return }

        let token = await appState.keychain.loadToken()
        guard let token else { return }

        await appState.apiClient.configure(baseURL: config.gitlabURL, token: token)

        await MainActor.run { appState.isLoading = true }

        do {
            let currentUser = try await appState.apiClient.fetchCurrentUser()
            await MainActor.run { appState.currentUser = currentUser }

            try await appState.storage.resetExpiredSnoozes()

            let results = await withTaskGroup(of: (String, Result<[MRDisplayItem], Error>).self) { group in
                for repoPath in config.repositories {
                    group.addTask {
                        do {
                            let items = try await self.processRepo(
                                repoPath: repoPath, config: config, currentUser: currentUser, appState: appState
                            )
                            return (repoPath, .success(items))
                        } catch {
                            return (repoPath, .failure(error))
                        }
                    }
                }
                var all: [(String, Result<[MRDisplayItem], Error>)] = []
                for await result in group {
                    all.append(result)
                }
                return all
            }

            var items: [MRDisplayItem] = []
            var failedRepos: [String] = []
            for (repoPath, result) in results {
                switch result {
                case .success(let repoItems): items.append(contentsOf: repoItems)
                case .failure: failedRepos.append(repoPath)
                }
            }

            let pending = items.filter(\.isActive)

            await MainActor.run {
                appState.mergeRequests = items
                appState.pendingCount = pending.count
                appState.isLoading = false
                appState.lastError = failedRepos.isEmpty
                    ? nil
                    : "Не удалось обновить: \(failedRepos.joined(separator: ", "))"
            }

            if config.reminderEnabled, let oldestPending = pending.map(\.updatedAt).min() {
                await appState.notifications.scheduleReminder(
                    anchor: oldestPending,
                    count: pending.count,
                    afterMinutes: config.reminderIntervalMinutes
                )
            } else {
                await appState.notifications.cancelReminder()
            }

        } catch {
            await MainActor.run {
                appState.isLoading = false
                appState.lastError = error.localizedDescription
            }
        }
    }

    private func processRepo(
        repoPath: String, config: AppConfig, currentUser: GitLabUser, appState: AppState
    ) async throws -> [MRDisplayItem] {
        let project = try await appState.apiClient.fetchProject(path: repoPath)
        let mrs = try await appState.apiClient.fetchOpenMRs(projectId: project.id)

        let ignoredLabels = Set(config.ignoredLabels.map { $0.lowercased() })
        let filtered = mrs.filter { mr in
            !mr.hasConflicts && (!config.excludeDrafts || !mr.isDraft)
                && ignoredLabels.isDisjoint(with: mr.labels.map { $0.lowercased() })
        }

        let relevant: [GitLabMR]
        switch config.mrFilter {
        case .allWithoutMyReview:
            var keep: [GitLabMR] = []
            for mr in filtered {
                let approvals = try await appState.apiClient.fetchApprovals(
                    projectId: project.id, mrIid: mr.iid
                )
                let alreadyApproved = approvals.approvedBy.contains {
                    $0.user.id == currentUser.id
                }
                if !alreadyApproved {
                    keep.append(mr)
                } else if let existing = try? await appState.storage.fetchMRRecord(
                    gitlabId: mr.id, projectPath: repoPath
                ), let mrId = existing.id {
                    let userState = try? await appState.storage.userState(for: mrId)
                    if userState?.status == .pending || userState?.status == .snoozed {
                        let alreadyRecorded = (try? await appState.storage.hasEvent(.approved, mrId: mrId)) ?? false
                        if !alreadyRecorded {
                            let newState = MRUserStateRecord(
                                mrId: mrId, status: .approved, snoozedUntil: nil, updatedAt: Date()
                            )
                            try? await appState.storage.upsertUserState(newState)
                            try? await appState.storage.recordEvent(.init(
                                id: nil, mrId: mrId, eventType: .approved, occurredAt: Date(),
                                extraJSON: ReviewEventRecord.metaJSON(title: mr.title, url: mr.webURL, mrIid: mr.iid, projectPath: repoPath)
                            ))
                        }
                    }
                }
            }
            relevant = keep
        case .assignedToMe:
            relevant = filtered
        }

        var seenIds = Set<Int>()
        for mr in relevant { seenIds.insert(mr.id) }

        let items = try await withThrowingTaskGroup(of: MRDisplayItem?.self) { group in
            for mr in relevant {
                group.addTask {
                    try await self.processMR(
                        mr: mr, repoPath: repoPath, project: project, config: config,
                        currentUser: currentUser, appState: appState
                    )
                }
            }
            var results: [MRDisplayItem] = []
            for try await item in group {
                if let item { results.append(item) }
            }
            return results
        }

        try await appState.storage.deleteMRsNotIn(gitlabIds: seenIds, projectPath: repoPath)

        return items
    }

    private func processMR(
        mr: GitLabMR, repoPath: String, project: GitLabProject, config: AppConfig,
        currentUser: GitLabUser, appState: AppState
    ) async throws -> MRDisplayItem? {
        let existing = try await appState.storage.fetchMRRecord(
            gitlabId: mr.id, projectPath: repoPath
        )

        let approvals = try await appState.apiClient.fetchApprovals(
            projectId: project.id, mrIid: mr.iid
        )
        let discussions = (try? await appState.apiClient.fetchDiscussions(
            projectId: project.id, mrIid: mr.iid
        )) ?? []
        let resolvableDiscussions = discussions.filter(\.isResolvable)
        let discussionsTotal = resolvableDiscussions.count
        let discussionsResolved = resolvableDiscussions.filter(\.isResolved).count

        let record = MRRecord(
            id: existing?.id,
            gitlabId: mr.id,
            projectPath: repoPath,
            title: mr.title,
            url: mr.webURL,
            authorUsername: mr.author.username,
            updatedAt: mr.updatedAt,
            lastCommitSha: mr.sha ?? "",
            createdAt: mr.createdAt,
            mrIid: mr.iid,
            projectId: project.id,
            approvalsCount: approvals.approvedBy.count,
            approvalsRequired: approvals.approvalsRequired,
            lastSeenNoteId: existing?.lastSeenNoteId ?? 0
        )

        let mrId = try await appState.storage.upsertMR(record)

        if let existing {
            let changed = mr.updatedAt > existing.updatedAt
                || (mr.sha != nil && mr.sha != existing.lastCommitSha)

            if changed {
                let state = try await appState.storage.userState(for: mrId)
                if state?.status == .snoozed || state?.status == .approved {
                    let newState = MRUserStateRecord(
                        mrId: mrId, status: .pending, snoozedUntil: nil, updatedAt: Date()
                    )
                    try await appState.storage.upsertUserState(newState)
                    try await appState.storage.recordEvent(.init(
                        id: nil, mrId: mrId, eventType: .changed,
                        occurredAt: Date(),
                        extraJSON: ReviewEventRecord.metaJSON(title: mr.title, url: mr.webURL)
                    ))
                    if config.systemNotificationsEnabled {
                        await appState.notifications.notifyMRChanged(
                            title: mr.title, url: mr.webURL
                        )
                    }
                }
            }

            // Check for new @mentions in notes
            if config.systemNotificationsEnabled {
                let lastNoteId = existing.lastSeenNoteId
                let notes = (try? await appState.apiClient.fetchNotes(
                    projectId: project.id, mrIid: mr.iid
                )) ?? []
                let newNotes = notes.filter { $0.id > lastNoteId && !$0.system }
                let mentions = newNotes.filter {
                    $0.body.localizedCaseInsensitiveContains("@\(currentUser.username)")
                }
                if !mentions.isEmpty {
                    await appState.notifications.notifyMention(
                        mrTitle: mr.title,
                        author: mentions[0].author.username,
                        url: mr.webURL
                    )
                }
                if let maxId = notes.map(\.id).max(), maxId > lastNoteId {
                    try? await appState.storage.updateLastSeenNoteId(mrId: mrId, noteId: maxId)
                }
            }
        } else {
            let initialState = MRUserStateRecord(
                mrId: mrId, status: .pending, snoozedUntil: nil, updatedAt: Date()
            )
            try await appState.storage.upsertUserState(initialState)

            try await appState.storage.recordEvent(.init(
                id: nil, mrId: mrId, eventType: .changed,
                occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: mr.title, url: mr.webURL)
            ))
            if config.systemNotificationsEnabled {
                await appState.notifications.notifyNewMR(
                    title: mr.title, url: mr.webURL
                )
            }

            // Seed lastSeenNoteId for new MRs so we don't spam on first poll
            let notes = (try? await appState.apiClient.fetchNotes(
                projectId: project.id, mrIid: mr.iid
            )) ?? []
            if let maxId = notes.map(\.id).max() {
                try? await appState.storage.updateLastSeenNoteId(mrId: mrId, noteId: maxId)
            }
        }

        let userState = try await appState.storage.userState(for: mrId)
        var effectiveStatus = userState?.status ?? .pending
        var effectiveSnoozedUntil = userState?.snoozedUntil

        // Auto-approve when required approvals are fully gathered
        let fullyApproved = approvals.approvalsRequired > 0
            && approvals.approvedBy.count >= approvals.approvalsRequired
        if fullyApproved && (effectiveStatus == .pending || effectiveStatus == .snoozed) {
            let newState = MRUserStateRecord(
                mrId: mrId, status: .approved, snoozedUntil: nil, updatedAt: Date()
            )
            try? await appState.storage.upsertUserState(newState)
            try? await appState.storage.recordEvent(.init(
                id: nil, mrId: mrId, eventType: .approved, occurredAt: Date(),
                extraJSON: ReviewEventRecord.metaJSON(title: mr.title, url: mr.webURL, mrIid: mr.iid, projectPath: repoPath)
            ))
            effectiveStatus = .approved
            effectiveSnoozedUntil = nil
        }

        guard let url = URL(string: mr.webURL) else { return nil }

        return MRDisplayItem(
            id: mrId,
            gitlabId: mr.id,
            projectPath: repoPath,
            title: mr.title,
            url: url,
            author: mr.author.username,
            updatedAt: mr.updatedAt,
            createdAt: mr.createdAt,
            status: effectiveStatus,
            snoozedUntil: effectiveSnoozedUntil,
            mrIid: mr.iid,
            projectId: project.id,
            approvalsCount: approvals.approvedBy.count,
            approvalsRequired: approvals.approvalsRequired,
            discussionsResolved: discussionsResolved,
            discussionsTotal: discussionsTotal
        )
    }
}
