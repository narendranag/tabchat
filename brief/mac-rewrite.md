# Brief — Tabchat for Mac, rewritten in Swift

Replaces `brief/mac-refactor.md` (the Electron refactor). Agreed with Narendra on 2026-10-13.

## Decisions

| Question | Answer |
| --- | --- |
| Stack | Swift + SwiftUI/AppKit + WKWebView (DEV-GUIDELINES' "Mac-only, deep OS hooks" exception). Fallback: clean Electron + TypeScript rewrite if the engine spike fails. |
| Minimum macOS | 14 Sonoma (`WKWebsiteDataStore(forIdentifier:)` for separate sign-ins) |
| Repo | Keep `narendranag/tabchat`; Linux code on the `Linux` branch (tag `upstream-final`), `main` clean; built in public |
| Name | Tabchat (credit MMV2408/tabchat, MIT, in the README) |
| Layout | Sidebar of service icons (Ferdium/Rambox style), not a title-bar tab strip |
| Languages | English only |
| Architecture | Apple Silicon only, unsigned local `.dmg` first |

## Features

| v1 | Later | Dropped |
| --- | --- | --- |
| Services: WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, custom sites | Split view | Linux packaging, D-Bus, GNOME DND |
| Several accounts per service, each its own sign-in | `Cmd+K` palette | Upstream updater, donate, changelog, what's new |
| One Microsoft sign-in shared by Teams, Outlook, OneDrive | Duplicate tab, incognito tab | Dutch |
| Unread per tab, Dock badge, menu bar dot | Tab sleep | |
| Notification click → its tab | Link-opening browser choice | |
| Close keeps running; menu bar icon | Card reorder / hide | |
| Pause notifications (1h, until tomorrow 08:00, until off) | | |
| Find, downloads, back/forward/reload/home | | |
| Start at login, optionally hidden | | |
| Light/dark following the system | | |

## Architecture

```
TabchatApp (SwiftUI app, menu bar extra, app menu with Cmd shortcuts)
├── Store            tabs, profiles, settings → JSON in ~/Library/Application Support/Tabchat
├── Profile          one WKWebsiteDataStore per sign-in ("microsoft-work" shared by
│                    Teams/Outlook/OneDrive; "whatsapp-1", "whatsapp-2" separate)
├── TabController    one WKWebView per tab, created on demand, dropped on sleep
├── Bridge (JS)      injected user script: shims window.Notification, reports unread
│                    → WKScriptMessageHandler
├── Notifier         UNUserNotificationCenter (honours Focus); click selects tab; pause timer
├── Badge            NSDockTile badge + menu bar dot = sum of unread
├── ServiceCatalog   per service: URL, icon, user agent, unread rule (title "(3) …" or selector)
└── LoginItem        SMAppService
```

## Phases

0. **Decisions** — done (table above).
1. **Engine spike** (throwaway, `spike/`): one WKWebView per service. Go/no-go checks:
   sign-in survives restart; two WhatsApp accounts stay separate; one Microsoft sign-in covers
   Teams/Outlook/OneDrive; notifications arrive via the shim; Teams call (mic, camera) and screen
   share; Discord voice and screen share; Brightspace school SSO. Result → `DECISIONS.md`.
   Narendra does every sign-in.
2. **Skeleton**: XcodeGen `project.yml`, `just build|run|test`, swiftformat + swiftlint, XCTest,
   GitHub Actions lint → test → build.
   Dashboard before this phase.
3. **Core**: sidebar, catalog, custom sites, profiles, persistence, navigation, find, downloads,
   external links, offline error screen with retry.
4. **Mac integration**: unread (tab, Dock, menu bar), notifications → tab, pause, close keeps
   running, login item, app menu and shortcuts (`Cmd+1…9`, `Cmd+W`, `Cmd+Shift+T`, `Ctrl+Tab`).
5. **The rest**: split view, `Cmd+K`, tab sleep, duplicate/incognito, card order, settings window.
6. **Packaging**: unsigned `.app`/`.dmg` locally. Later, if Narendra approves the cost:
   Developer ID, notarisation in CI, Sparkle updates.

Docs: `docs-build --init` after phase 2; README credits upstream.
