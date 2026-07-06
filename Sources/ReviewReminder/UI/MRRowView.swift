import SwiftUI
import AppKit

// MARK: - Action Popover

struct MRActionPopover: View {
    @Environment(AppState.self) private var appState
    let mr: MRDisplayItem
    @Binding var isPresented: Bool

    @State private var copied = false
    @State private var showApproveConfirm = false

    private let snoozeDurations: [(label: String, minutes: Int)] = [
        ("5 минут",   5),
        ("15 минут",  15),
        ("30 минут",  30),
        ("1 час",     60),
        ("2 часа",    120),
        ("До завтра", 60 * 24),
    ]

    var body: some View {
        if showApproveConfirm {
            approveConfirmView
        } else {
            actionsList
        }
    }

    private var approveConfirmView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Одобрить МР «\(mr.title)»?")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Отмена") {
                    showApproveConfirm = false
                }
                Spacer()
                Button("Одобрить") {
                    appState.approveMR(item: mr)
                    showApproveConfirm = false
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(width: 230)
    }

    private var actionsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Copy link
            popoverButton(copied ? "Скопировано!" : "Копировать ссылку",
                          icon: copied ? "checkmark" : "link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mr.url.absoluteString, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            }

            if AppConfig.load().taskTrackerEnabled,
               let taskId = mr.taskId(pattern: AppConfig.load().taskTrackerPattern) {
                popoverButton("Перейти к задаче \(taskId)", icon: "arrow.up.right.square") {
                    let base = AppConfig.load().taskTrackerBaseURL
                    if let url = URL(string: base + taskId) {
                        NSWorkspace.shared.open(url)
                    }
                    isPresented = false
                }
            }

            Divider().padding(.vertical, 2)

            // Snooze section
            snoozeSectionLabel
            ForEach(snoozeDurations, id: \.minutes) { item in
                popoverButton(item.label, icon: "clock", indent: true) {
                    appState.snoozeMR(id: mr.id, minutes: item.minutes)
                    isPresented = false
                }
            }

            Divider().padding(.vertical, 2)

            popoverButton(
                mr.status == .ignored ? "Показать снова" : "Игнорировать",
                icon: mr.status == .ignored ? "eye" : "eye.slash"
            ) {
                if mr.status == .ignored {
                    appState.dismissIgnore(id: mr.id)
                } else {
                    appState.ignoreMR(id: mr.id)
                }
                isPresented = false
            }

            Divider().padding(.vertical, 2)

            if mr.canApprove && mr.status != .approved {
                popoverButton("Одобрить", icon: "checkmark.seal", color: .blue) {
                    showApproveConfirm = true
                }
            }
        }
        .padding(6)
        .frame(width: 230)
    }

    private var snoozeSectionLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .frame(width: 16)
            Text("Отложить")
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func popoverButton(
        _ title: String,
        icon: String,
        color: Color = .primary,
        indent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if indent {
                    Color.clear.frame(width: 16)
                    Image(systemName: icon)
                        .frame(width: 12)
                        .foregroundStyle(.tertiary)
                        .font(.system(size: 11))
                } else {
                    Image(systemName: icon)
                        .frame(width: 16)
                        .foregroundStyle(color == .primary ? .secondary : color)
                }
                Text(title)
                    .font(.system(size: indent ? 12 : 13))
                    .foregroundStyle(indent ? .secondary : color)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, indent ? 4 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverRowButtonStyle())
    }
}

struct PopoverRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
    }
}

// MARK: - MR Row

struct MRRowView: View {
    @Environment(AppState.self) private var appState
    let mr: MRDisplayItem

    @State private var isHovered = false
    @State private var showPopover = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Button {
                    NSWorkspace.shared.open(mr.url)
                    appState.recordViewed(id: mr.id)
                } label: {
                    Text(mr.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Text("@\(mr.author)").font(.caption2).foregroundStyle(.secondary)
                    Text("·").font(.caption2).foregroundStyle(.tertiary)
                    Text(mr.ageDescription)
                        .font(.caption2)
                        .foregroundStyle(mr.isOld ? .orange : .secondary)
                    if let snoozeDesc = mr.snoozeUntilDescription {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        Text(snoozeDesc).font(.caption2).foregroundStyle(.orange)
                    }
                    if mr.approvalsRequired > 0 {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        approvalsLabel
                    }
                    if mr.discussionsTotal > 0 {
                        Text("·").font(.caption2).foregroundStyle(.tertiary)
                        discussionsLabel
                    }
                }
            }

            // Always-visible actions button
            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        showPopover
                            ? Color.primary.opacity(0.1)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 5)
                    )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPopover, arrowEdge: .trailing) {
                MRActionPopover(mr: mr, isPresented: $showPopover)
                    .environment(appState)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(isHovered ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onAppear { showPopover = false }
    }

    @ViewBuilder
    private var approvalsLabel: some View {
        let count = mr.approvalsCount
        let required = mr.approvalsRequired
        let done = count >= required
        HStack(spacing: 2) {
            Image(systemName: done ? "checkmark.seal.fill" : "checkmark.seal")
                .font(.caption2)
                .foregroundStyle(done ? .green : .secondary)
            Text("\(count)/\(required)")
                .font(.caption2)
                .foregroundStyle(done ? .green : .secondary)
        }
    }

    private var discussionsLabel: some View {
        let resolved = mr.discussionsResolved
        let total = mr.discussionsTotal
        let done = resolved >= total
        return HStack(spacing: 2) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption2)
                .foregroundStyle(done ? .green : .secondary)
            Text("\(resolved)/\(total)")
                .font(.caption2)
                .foregroundStyle(done ? .green : .secondary)
        }
    }

    private var statusColor: Color {
        switch mr.status {
        case .pending:  mr.isOld ? .orange : .blue
        case .snoozed:  .gray
        case .ignored:  .gray.opacity(0.4)
        case .approved: .green
        }
    }
}

// MARK: - Reviewed MR Row

struct ReviewedMRRow: View {
    @Environment(AppState.self) private var appState
    let mr: MRDisplayItem
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green.opacity(0.45))
                .frame(width: 7, height: 7)

            Button {
                NSWorkspace.shared.open(mr.url)
                appState.recordViewed(id: mr.id)
            } label: {
                Text(mr.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                appState.undoReviewed(id: mr.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Вернуть в очередь")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}
