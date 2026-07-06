# Review Reminder — распространение и установка

## Вариант 1: передать готовый .app (рекомендуется)

### Шаг 1 — заархивирfnm приложение

```bash
cd ~/Applications
zip -r ReviewReminder.zip ReviewReminder.app
```

Передай `ReviewReminder.zip` коллеге (AirDrop, Slack, общая папка).

### Шаг 2 — коллега устанавливает

```bash
unzip ReviewReminder.zip -d ~/Applications/
xattr -rd com.apple.quarantine ~/Applications/ReviewReminder.app
open ~/Applications/ReviewReminder.app
```

---

## Вариант 2: собрать из исходников

**Требуется:** macOS 14+, Xcode Command Line Tools (`xcode-select --install`).

```bash
# Клонировать/скопировать репозиторий
cd /path/to/reviewer

# Собрать и установить
swift build -c release
bash Scripts/install.sh
```

Скрипт собирает бандл, подписывает, копирует в `~/Applications` и запускает.

---

## Первый запуск

После установки иконка появится в строке меню (правый верхний угол).

1. Нажми на иконку → **Настройки**
2. Вкладка **GitLab**:
   - **URL** — адрес GitLab, например `https://gitlab.example.com`
   - **Токен** — Personal Access Token с правами `api` (нужно для approve МР; `read_api` хватит без approve)
   - **Репозитории** — пути проектов, например `group/project-one, group/project-two`
3. Нажми **Сохранить** — приложение сразу сделает первый запрос

### Создание токена в GitLab

GitLab → аватар → **Edit profile** → **Access Tokens** → **Add new token**

- Name: любое, например `review-reminder`
- Scopes: `api` (для approve; `read_api` без approve)
- Expiration: по желанию

---

## Системные требования

- macOS 14 Sonoma или новее
- Доступ к GitLab по сети (VPN если нужен)
- Apple Developer account **не требуется**

---

## Удаление

```bash
pkill -x ReviewReminder 2>/dev/null
rm -rf ~/Applications/ReviewReminder.app
# База данных и настройки (опционально):
rm -rf ~/Library/Application\ Support/ReviewReminder
```
