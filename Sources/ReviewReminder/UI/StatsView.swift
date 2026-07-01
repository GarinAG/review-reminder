import AppKit
import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var appState
    @State private var mrStates: [Int64: String] = [:]

    var body: some View {
        Group {
            if let stats = appState.stats {
                statsContent(stats)
            } else {
                ProgressView("Загрузка статистики...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { appState.refreshStats() }
        .task(id: appState.stats?.recentEvents.count) { await fetchMRStates() }
        .padding(24)
    }

    private func fetchMRStates() async {
        guard let stats = appState.stats else { return }
        let baseURL = AppConfig.load().gitlabURL.trimmingCharacters(in: .init(charactersIn: "/"))
        let approvedEvents = stats.recentEvents.filter { $0.eventType == .approved && $0.id != nil }

        for event in approvedEvents {
            if let eid = event.id { mrStates[eid] = "loading" }
        }

        await withTaskGroup(of: (Int64, String)?.self) { group in
            for event in approvedEvents {
                guard let eid = event.id else { continue }
                let projectPath: String
                let mrIid: Int
                if let p = event.meta?.projectPath, let i = event.meta?.mrIid {
                    projectPath = p; mrIid = i
                } else if let urlStr = event.meta?.url,
                          let parsed = Self.parseMRPath(from: urlStr, baseURL: baseURL) {
                    projectPath = parsed.projectPath; mrIid = parsed.mrIid
                } else {
                    mrStates.removeValue(forKey: eid)
                    continue
                }
                group.addTask {
                    guard let mr = try? await appState.apiClient.fetchMRByPath(
                        projectPath: projectPath, mrIid: mrIid
                    ) else { return nil }
                    return (eid, mr.state)
                }
            }
            for await result in group {
                if let (eid, state) = result { mrStates[eid] = state }
                else { /* remove loading on failure */ }
            }
        }
        // Clear any remaining "loading" that failed
        for (k, v) in mrStates where v == "loading" { mrStates.removeValue(forKey: k) }
    }

    private static func parseMRPath(from urlString: String, baseURL: String) -> (projectPath: String, mrIid: Int)? {
        guard urlString.hasPrefix(baseURL) else { return nil }
        let path = String(urlString.dropFirst(baseURL.count)).trimmingCharacters(in: .init(charactersIn: "/"))
        let parts = path.components(separatedBy: "/-/merge_requests/")
        guard parts.count == 2,
              let iid = Int(parts[1].components(separatedBy: "?")[0].components(separatedBy: "#")[0])
        else { return nil }
        return (projectPath: parts[0], mrIid: iid)
    }

    private func statsContent(_ stats: ReviewStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Статистика")
                        .font(.title2.bold())
                    Spacer()
                    Button("Сбросить статистику") {
                        appState.resetStats()
                    }
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
                    .font(.caption)
                }

                // Summary cards
                HStack(spacing: 16) {
                    StatCard(title: "Просмотрено", value: "\(stats.totalReviewed)", icon: "eye.fill", color: .blue)
                    StatCard(title: "Одобрено", value: "\(stats.totalApproved)", icon: "checkmark.circle.fill", color: .green)
                    StatCard(title: "Отложено", value: "\(stats.totalSnoozed)", icon: "clock.fill", color: .orange)
                    StatCard(title: "Игнорировано", value: "\(stats.totalIgnored)", icon: "eye.slash.fill", color: .gray)
                }

                Divider()

                // Activity chart (events per day, last 30 days)
                let dailyData = aggregateByDay(events: stats.recentEvents, days: 30)
                if !dailyData.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Активность (последние 30 дней)")
                            .font(.headline)

                        Chart(dailyData) { item in
                            BarMark(
                                x: .value("День", item.date, unit: .day),
                                y: .value("События", item.count)
                            )
                            .foregroundStyle(by: .value("Тип", item.type))
                        }
                        .chartLegend(position: .bottom)
                        .frame(height: 180)
                    }
                }

                Divider()

                // Recent events list
                VStack(alignment: .leading, spacing: 4) {
                    Text("Последние события")
                        .font(.headline)
                        .padding(.bottom, 4)

                    ForEach(Array(stats.recentEvents.prefix(30).enumerated()), id: \.offset) { _, event in
                        eventRow(event)
                        if event.id != stats.recentEvents.prefix(30).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventRow(_ event: ReviewEventRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: event.eventType.icon)
                .foregroundStyle(event.eventType.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                if let meta = event.meta, !meta.title.isEmpty {
                    if let urlStr = meta.url, let url = URL(string: urlStr) {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Text(meta.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .help(meta.title)
                    } else {
                        Text(meta.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("МР #\(event.mrId)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Text(event.eventType.label)
                    .font(.caption2)
                    .foregroundStyle(event.eventType.color)
            }

            Spacer()

            if event.eventType == .approved, let eid = event.id {
                mrStateBadge(for: eid)
            }

            Text(event.occurredAt.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func mrStateBadge(for eventId: Int64) -> some View {
        if let state = mrStates[eventId] {
            if state == "loading" {
                ProgressView().scaleEffect(0.5).frame(width: 24, height: 14)
            } else {
                mrStateLabel(state)
            }
        }
    }

    private func mrStateLabel(_ state: String) -> some View {
        let (label, color): (String, Color) = {
            switch state {
            case "merged": return ("Влит", .purple)
            case "closed": return ("Закрыт", .gray)
            default:       return ("Открыт", .orange)
            }
        }()
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func aggregateByDay(events: [ReviewEventRecord], days: Int) -> [DayActivity] {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -days, to: Date())!

        var buckets: [Date: [String: Int]] = [:]
        for event in events where event.occurredAt >= start {
            let day = calendar.startOfDay(for: event.occurredAt)
            buckets[day, default: [:]][event.eventType.label, default: 0] += 1
        }

        return buckets.flatMap { day, counts in
            counts.map { type, count in
                DayActivity(date: day, type: type, count: count)
            }
        }.sorted { $0.date < $1.date }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DayActivity: Identifiable {
    let id = UUID()
    let date: Date
    let type: String
    let count: Int
}

extension ReviewEventType {
    var label: String {
        switch self {
        case .reviewed:  "Просмотрен"
        case .approved:  "Одобрен"
        case .snoozed:   "Отложен"
        case .ignored:   "Проигнорирован"
        case .changed:   "МР обновлён"
        case .dismissed: "Отмена игнора"
        }
    }

    var icon: String {
        switch self {
        case .reviewed:  "eye.fill"
        case .approved:  "checkmark.circle.fill"
        case .snoozed:   "clock.fill"
        case .ignored:   "eye.slash.fill"
        case .changed:   "arrow.triangle.2.circlepath"
        case .dismissed: "eye"
        }
    }

    var color: Color {
        switch self {
        case .reviewed:  .blue
        case .approved:  .green
        case .snoozed:   .orange
        case .ignored:   .gray
        case .changed:   .purple
        case .dismissed: .cyan
        }
    }
}
