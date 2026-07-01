import SwiftUI

@main
struct ReviewReminderApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel(count: appState.pendingCount)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }

        Window("Статистика", id: "stats") {
            StatsView()
                .environment(appState)
                .frame(minWidth: 580, maxWidth: .infinity, minHeight: 430, maxHeight: .infinity)
        }
        .windowResizability(.automatic)
        .defaultSize(width: 720, height: 540)
        .commandsRemoved()
    }
}

struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: count > 0 ? "exclamationmark.circle.fill" : "checkmark.circle")
                .foregroundStyle(count > 0 ? .orange : .secondary)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }
}
