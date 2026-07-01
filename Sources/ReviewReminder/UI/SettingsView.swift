import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var config = AppConfig.load()
    @State private var tokenInput: String = ""
    @State private var newRepo: String = ""
    @State private var newIgnoredLabel: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showTokenField = false
    @State private var isLoadingProjects = false
    @State private var availableProjects: [GitLabProject] = []
    @State private var showProjectPicker = false
    @State private var projectsError: String?

    var body: some View {
        TabView {
            gitlabTab
                .tabItem { Label("GitLab", systemImage: "server.rack") }

            notificationsTab
                .tabItem { Label("Уведомления", systemImage: "bell") }

            filtersTab
                .tabItem { Label("Фильтры", systemImage: "line.3.horizontal.decrease.circle") }

            generalTab
                .tabItem { Label("Основные", systemImage: "gearshape") }
        }
        .padding(20)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 380, maxHeight: .infinity)
        .onAppear {
            config = AppConfig.load()
            Task {
                tokenInput = await appState.keychain.loadToken() ?? ""
            }
        }
    }

    // MARK: - Tabs

    private var gitlabTab: some View {
        Form {
            Section("GitLab инстанс") {
                LabeledContent("URL") {
                    TextField("https://gitlab.company.com", text: $config.gitlabURL)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Токен доступа") {
                    HStack {
                        if showTokenField {
                            TextField("glpat-...", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("glpat-...", text: $tokenInput)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button {
                            showTokenField.toggle()
                        } label: {
                            Image(systemName: showTokenField ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if let user = appState.currentUser {
                    LabeledContent("Вошли как") {
                        HStack {
                            Text("@\(user.username)")
                                .foregroundStyle(.secondary)
                            Text("(\(user.name))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Репозитории") {
                if config.repositories.isEmpty {
                    Text("Репозитории не добавлены")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                ForEach(config.repositories, id: \.self) { repo in
                    HStack {
                        Text(repo)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button {
                            config.repositories.removeAll { $0 == repo }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("group/repository", text: $newRepo)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addRepo)
                    Button("Добавить", action: addRepo)
                        .disabled(newRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                HStack(spacing: 8) {
                    Button {
                        loadProjects()
                    } label: {
                        if isLoadingProjects {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            Text("Загрузка...")
                        } else {
                            Image(systemName: "arrow.down.circle")
                            Text("Выбрать из GitLab")
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoadingProjects || config.gitlabURL.isEmpty || tokenInput.isEmpty)

                    if let err = projectsError {
                        Text(err).font(.caption2).foregroundStyle(.red)
                    }
                }
            }

            saveRow
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(
                projects: availableProjects,
                selected: $config.repositories
            )
        }
    }

    private var notificationsTab: some View {
        Form {
            Section("Системные уведомления") {
                Toggle("Включить системные уведомления", isOn: $config.systemNotificationsEnabled)
            }

            Section("Напоминания") {
                Toggle("Периодические напоминания", isOn: $config.reminderEnabled)

                if config.reminderEnabled {
                    Picker("Напоминать каждые", selection: $config.reminderIntervalMinutes) {
                        Text("15 мин").tag(15)
                        Text("30 мин").tag(30)
                        Text("1 час").tag(60)
                        Text("2 часа").tag(120)
                    }
                }
            }

            saveRow
        }
        .formStyle(.grouped)
    }

    private var filtersTab: some View {
        Form {
            Section("Фильтр МРов") {
                Picker("Показывать", selection: $config.mrFilter) {
                    ForEach(MRFilterMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section("Исключения") {
                Toggle("Исключать черновики / WIP", isOn: $config.excludeDrafts)

                ForEach(config.ignoredLabels, id: \.self) { label in
                    HStack {
                        Text(label)
                        Spacer()
                        Button {
                            config.ignoredLabels.removeAll { $0 == label }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Игнорировать МР с меткой", text: $newIgnoredLabel)
                        .onSubmit(addIgnoredLabel)
                    Button("Добавить", action: addIgnoredLabel)
                        .disabled(newIgnoredLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            saveRow
        }
        .formStyle(.grouped)
    }

    private var generalTab: some View {
        Form {
            Section("Опрос") {
                Picker("Проверять каждые", selection: $config.pollIntervalMinutes) {
                    Text("5 мин").tag(5)
                    Text("10 мин").tag(10)
                    Text("30 мин").tag(30)
                }
            }

            Section("Система") {
                Toggle("Запускать при входе", isOn: Binding(
                    get: { config.launchAtLogin },
                    set: { val in
                        config.launchAtLogin = val
                        appState.setLaunchAtLogin(val)
                    }
                ))
            }

            Section("Трекер задач") {
                Toggle("Показывать переход к задаче трекера", isOn: $config.taskTrackerEnabled)
                if config.taskTrackerEnabled {
                    LabeledContent("Ссылка на трекер") {
                        TextField("https://tracker.yandex.ru/", text: $config.taskTrackerBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Regex номера задачи") {
                        TextField("([A-Z]+-\\d+)", text: $config.taskTrackerPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                    Text("По умолчанию: ^([A-Z]+-\\d+): — ищет PROJECT-123 в начале названия МР")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            saveRow
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private var saveRow: some View {
        HStack {
            if let msg = saveMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Сохранить") { save() }
                .disabled(isSaving)
                .buttonStyle(.borderedProminent)
        }
    }

    private func loadProjects() {
        isLoadingProjects = true
        projectsError = nil
        Task {
            do {
                await appState.apiClient.configure(baseURL: config.gitlabURL, token: tokenInput)
                let projects = try await appState.apiClient.fetchUserProjects()
                availableProjects = projects.sorted { $0.pathWithNamespace < $1.pathWithNamespace }
                showProjectPicker = true
            } catch {
                projectsError = error.localizedDescription
            }
            isLoadingProjects = false
        }
    }

    private func addRepo() {
        let r = newRepo.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty, !config.repositories.contains(r) else { return }
        config.repositories.append(r)
        newRepo = ""
    }

    private func addIgnoredLabel() {
        let l = newIgnoredLabel.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty, !config.ignoredLabels.contains(l) else { return }
        config.ignoredLabels.append(l)
        newIgnoredLabel = ""
    }

    private func save() {
        guard config.gitlabURL.isEmpty || config.gitlabURLIsSecure else {
            saveMessage = "⚠︎ GitLab URL должен начинаться с https://"
            return
        }
        isSaving = true
        Task {
            if !tokenInput.isEmpty {
                try? await appState.keychain.saveToken(tokenInput)
            }
            config.save()
            saveMessage = "Сохранено"
            isSaving = false
            appState.refreshNow()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveMessage = nil
        }
    }
}

// MARK: - Project Picker Sheet

struct ProjectPickerSheet: View {
    let projects: [GitLabProject]
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var search = ""

    private var filtered: [GitLabProject] {
        guard !search.isEmpty else { return projects }
        return projects.filter {
            $0.pathWithNamespace.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Выбор репозиториев")
                    .font(.headline)
                Spacer()
                Text("\(selected.count) выбрано")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Готово") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск...", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // List
            if filtered.isEmpty {
                Spacer()
                Text("Ничего не найдено").foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered, id: \.id) { project in
                            projectRow(project)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private func projectRow(_ project: GitLabProject) -> some View {
        let path = project.pathWithNamespace
        let isOn = selected.contains(path)

        return Button {
            if isOn {
                selected.removeAll { $0 == path }
            } else {
                selected.append(path)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 1) {
                    Text(path.components(separatedBy: "/").last ?? path)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.accentColor.opacity(0.06) : Color.clear)
    }
}
