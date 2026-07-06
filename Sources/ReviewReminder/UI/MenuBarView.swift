import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    private var activeMRs: [MRDisplayItem] {
        appState.mergeRequests.filter(\.isActive)
    }
    private var snoozedMRs: [MRDisplayItem] {
        appState.mergeRequests.filter { $0.status == .snoozed && !$0.isActive }
    }
    private var reviewedMRs: [MRDisplayItem] {
        appState.mergeRequests.filter { $0.status == .approved }
    }

    // Group active MRs by repo name, sorted alphabetically
    private var groupedActiveMRs: [(repo: String, items: [MRDisplayItem])] {
        let grouped = Dictionary(grouping: activeMRs) { $0.repoName }
        return grouped.sorted { $0.key < $1.key }.map { (repo: $0.key, items: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if !AppConfig.load().isConfigured {
                notConfiguredView
            } else if appState.isLoading && appState.mergeRequests.isEmpty {
                loadingView
            } else if activeMRs.isEmpty && snoozedMRs.isEmpty && reviewedMRs.isEmpty {
                emptyView
            } else {
                mrListView
            }

            // Only show error when no data loaded (ignore non-critical decode errors)
            if let error = appState.lastError, appState.mergeRequests.isEmpty {
                Divider()
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .lineLimit(2)
            }

            if let error = appState.actionError {
                Divider()
                HStack {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                    Button {
                        appState.actionError = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            Divider()
            footer
        }
        .frame(width: 420)
        .onAppear {
            Task { appState.setup() }
            // .menuBarExtraStyle(.window) doesn't make its window key on open, so the first
            // hover/click just activates the app instead of hitting SwiftUI's hit-testing —
            // forcing activation here is what fixes the delayed hover / "needs two clicks" bug.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Reminder").font(.headline)
                if let user = appState.currentUser {
                    Text("@\(user.username)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if appState.isLoading {
                ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
            } else {
                Button {
                    appState.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13))
                }
                .buttonStyle(.plain)
                .help("Обновить")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Статистика") {
                openWindow(id: "stats")
                appState.refreshStats()
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            if let nextReminderDate = appState.nextReminderDate, appState.pendingCount > 0 {
                Text(MRDisplayItem.relativeDateDescription(
                    nextReminderDate, prefix: "напомню", tomorrowPrefix: "напомню завтра"
                ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                Spacer()
            }

            Button("Настройки") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Выход") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - State views

    private var notConfiguredView: some View {
        VStack(spacing: 8) {
            Image(systemName: "gear").font(.largeTitle).foregroundStyle(.secondary)
            Text("Не настроено").font(.headline)
            Text("Откройте Настройки и добавьте токен GitLab и репозитории.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24).frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        HStack {
            ProgressView()
            Text("Загрузка мерж-реквестов...").foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("Всё в порядке!").font(.headline)
            Text("Нет мерж-реквестов, требующих внимания.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(maxWidth: .infinity)
    }

    // MARK: - MR List (VStack, not Lazy — prevents ghost rows)

    @State private var listContentHeight: CGFloat = 0
    private let maxListHeight: CGFloat = 480

    private var mrListView: some View {
        let hasSnoozed = !snoozedMRs.isEmpty
        let hasReviewed = !reviewedMRs.isEmpty

        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(groupedActiveMRs.enumerated()), id: \.element.repo) { gi, group in
                    if groupedActiveMRs.count > 1 {
                        sectionHeader(group.repo, icon: "folder")
                    }
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { i, mr in
                        MRRowView(mr: mr).id(mr.id)
                        if i < group.items.count - 1 || gi < groupedActiveMRs.count - 1 || hasSnoozed || hasReviewed {
                            Divider().padding(.leading, 14)
                        }
                    }
                }

                if hasSnoozed {
                    sectionHeader("ОТЛОЖЕНЫ")
                    ForEach(Array(snoozedMRs.enumerated()), id: \.element.id) { i, mr in
                        MRRowView(mr: mr).id(mr.id)
                        if i < snoozedMRs.count - 1 || hasReviewed {
                            Divider().padding(.leading, 14)
                        }
                    }
                }

                if hasReviewed {
                    sectionHeader("ПРОВЕРЕНЫ")
                    ForEach(Array(reviewedMRs.enumerated()), id: \.element.id) { i, mr in
                        ReviewedMRRow(mr: mr).id(mr.id)
                        if i < reviewedMRs.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ListHeightKey.self, value: geo.size.height)
                }
            )
        }
        .frame(height: min(listContentHeight, maxListHeight))
        .onPreferenceChange(ListHeightKey.self) { listContentHeight = $0 }
    }

    private func sectionHeader(_ title: String, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }
}

private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
