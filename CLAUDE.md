# CLAUDE.md

Этот файл — инструкция для Claude Code (claude.ai/code) при работе с кодом в этом репозитории.

## Команды

```bash
task setup       # установка xcodegen (через Homebrew), генерация .xcodeproj
task open        # генерация проекта и открытие в Xcode
task release     # сборка Release .app с ad-hoc подписью
task install     # сборка + копирование в ~/Applications + запуск (нужен полный Xcode)
task install-swift  # сборка + установка БЕЗ Xcode (только SwiftPM + Scripts/install.sh)
task clean       # удаление build/ и .xcodeproj
```

`task install`/`task release` требуют полный Xcode (`xcodebuild`), а не только Command Line Tools. Если установлен
только CLT — использовать `task install-swift`, он не вызывает xcodegen/xcodebuild:

```bash
swift build -c release
bash Scripts/install.sh   # собирает bundle из .build/release, подписывает, ставит, запускает
```

## Архитектура

Приложение для трея macOS (без иконки в Dock — `LSUIElement=true`). Swift 6 strict concurrency везде.

**Точка входа:** `App/ReviewReminderApp.swift` — `@main`, объявляет `MenuBarExtra` (popover в трее), `Settings` scene и
`Window("stats")`.

**Состояние:** `App/AppState.swift` — класс `@Observable @MainActor`, общий для всех view через `.environment()`.
Владеет всеми сервисами. Все мутации МР идут через его action-методы (`snoozeMR`, `ignoreMR`,
`approveMR`).

**Сервисы (акторы):**

- `Core/GitLabAPIClient.swift` — GitLab REST API v4. Пагинация, ISO8601-даты, Bearer-авторизация. Методы: получение МР,
  approvals, notes, approve MR.
- `Core/StorageService.swift` — GRDB (SQLite). Миграции запускаются в `setup()`. Все операции с БД — `async throws`.
- `Core/PollingService.swift` — цикл `while isRunning`. Дёргает API, определяет изменения МР (по `updatedAt` + commit
  SHA), проверяет новые @упоминания в notes, обновляет `AppState` через `await MainActor.run`.
- `Core/NotificationService.swift` — `UNUserNotificationCenter` с delegate для показа уведомлений даже при активном
  приложении. Срабатывает на изменение МР, @упоминание, планирует периодическое напоминание.
- `Core/KeychainService.swift` — хранит GitLab-токен в системном Keychain (`kSecClassGenericPassword`), сервис
  `"com.reviewreminder"`.

**Модели:**

- `Models/GitLabModels.swift` — `Codable`-структуры под ответы GitLab API.
- `Models/DBModels.swift` — типы GRDB `FetchableRecord`/`PersistableRecord`. `MRStatus` и `ReviewEventType` — `String`
  -enum'ы, хранятся как raw values.
- `Models/MRDisplayItem.swift` — view-модель, объединяющая запись БД и состояние пользователя. Включает
  `approvalsCount`, `approvalsRequired`, `mrIid`, `projectId`. Вычисляемое `isActive` управляет счётчиком в трее.
- `Models/AppConfig.swift` — конфиг на `UserDefaults`. Токен живёт в Keychain отдельно. Вызывать `AppConfig.load()` /
  `config.save()` явно.

**UI:**

- `UI/MenuBarView.swift` — popover в трее (420pt шириной). Показывает активные МР сгруппированные по репо, секцию
  отложенных, секцию проверенных. Футер: Stats / Settings / Quit.
- `UI/MRRowView.swift` — строка МР. Всегда видимая кнопка `···` открывает `MRActionPopover`: копировать ссылку, submenu
  отложить, игнорировать, approve (через API), отметить проверенным.
- `UI/SettingsView.swift` — вкладки: GitLab (URL + токен + репо), Уведомления, Фильтры, Основные. Resizable окно.
  Сохранение по явной кнопке Save; триггерит немедленный poll.
- `UI/StatsView.swift` — bar chart на Swift Charts. Агрегирует `ReviewEventRecord` по дням. Кнопка сброса.

## Важные решения архитектуры

**Хранение токена:** только Keychain. Никогда в `UserDefaults` или plist-файлах.

**Определение изменений:** на каждом poll, если `mr.updatedAt > stored.updatedAt` ИЛИ commit SHA отличается → статус
сбрасывается на `pending` и летит уведомление. Это возвращает отложенные/approved МР на видное место после новых
коммитов.

**Проверка approval:** отдельный API-вызов на МР к `/approvals`. N+1 приемлем при типичном количестве МР (<50 на
проект).

**Определение упоминаний:** notes запрашиваются на МР при каждом poll. `lastSeenNoteId` трекается в БД. Уведомление
только для notes с `id > lastSeenNoteId`. Новые МР сидируют `lastSeenNoteId` без уведомления.

**Запуск при логине:** `SMAppService.mainApp.register()`. Требует приложение в `~/Applications` — install-скрипт
занимается размещением.

**Ad-hoc подпись:** `codesign --sign -`. `xattr -rd com.apple.quarantine` убирает предупреждение Gatekeeper после
копирования. Аккаунт Apple Developer не нужен.

## Подводные камни

**`Resources/Info.plist` НЕ должен содержать переменные сборки Xcode вроде `$(EXECUTABLE_NAME)` / `$(PRODUCT_NAME)`.**
Xcodegen/xcodebuild резолвят их во время сборки, но `Scripts/install.sh` и swift-build путь копируют `Info.plist` как
есть — нерезолвленные плейсхолдеры делают `CFBundleExecutable`/`CFBundleName` буквальными строками, и macOS отказывается
запускать приложение ("executable is missing"). Держать эти значения захардкоженными как `ReviewReminder`. Эта проблема
уже несколько раз ломала swift-build путь установки — проверять этот файл в первую очередь, если `task install-swift`
собрал приложение, которое не запускается.

## Зависимости

Управляются через Swift Package Manager (`Package.swift`):

- **GRDB.swift** `≥6.0.0` — SQLite ORM
- **Swift Charts** — встроен в macOS 13+, пакет не нужен

## Расположение БД

`~/Library/Application Support/ReviewReminder/reviewer.sqlite`

## Bundle

- Bundle ID: `com.reviewreminder`
- Бинарник: `ReviewReminder`
- Путь установки: `~/Applications/ReviewReminder.app`
