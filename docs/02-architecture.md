---
id: architecture
title: Architecture
order: 2
summary: "System components, data flow, and design decisions."
status: design
updated: 2026-10-13
audience: [developers]
depends_on: [index, overview]
related: []
defines: []
answers:
  - How is the app structured?
  - What are the main components?
  - How do services, profiles, and tabs relate?
---

# Architecture

The app is built as a SwiftUI app with AppKit where needed for menu bar and system integration. WKWebView instances are created on demand per tab; the system persists sign-in state in `WKWebsiteDataStore` objects identified by profile name.

## Component tree

```
TabchatApp (SwiftUI app entry point, menu bar extra, app menu with Cmd shortcuts)
├── Store                    single source of truth: tabs, profiles, settings
│                            persisted as JSON in ~/Library/Application Support/Tabchat
├── Profile                  one WKWebsiteDataStore per sign-in
│                            ("microsoft-work" shared by Teams/Outlook/OneDrive;
│                            "whatsapp-1", "whatsapp-2" separate)
├── TabController            manages one WKWebView per tab; creates on demand, drops on sleep
├── ServiceCatalog           per service: URL, icon, user agent, unread rule
├── Bridge (JavaScript)      user script injected into each tab
│                            • shims window.Notification
│                            • reports unread count to native code via WKScriptMessageHandler
├── Notifier                 UNUserNotificationCenter
│                            • sends native notifications for new messages
│                            • respects macOS Focus modes
│                            • pause timer (1h, until 08:00 tomorrow, until off)
│                            • notification click selects the service and brings window to front
├── Badge                    Dock tile badge (sum of all unread) + menu bar dot indicator
├── Sidebar                  icon + name per tab, drag-reorder, unread count
├── TabView                  WKWebView instance and toolbar (back/forward/reload/home/find/downloads)
└── LoginItem                SMAppService for start-at-login, optional hidden mode
```

## Data flow: opening a tab

1. User clicks a service in the sidebar.
2. `TabController` checks if a `WKWebView` exists for that profile; if not, creates one.
3. `WKWebView` loads the URL for that service, using the profile's `WKWebsiteDataStore` for cookies and site data.
4. JavaScript Bridge is injected; it replaces `window.Notification` with a callback to native code.
5. User signs in. Cookies and session storage are persisted in the profile's `WKWebsiteDataStore`.

## Data flow: new message notification

1. Web page script (e.g. Discord) displays a notification via `window.Notification("3 new messages")`.
2. Injected Bridge script intercepts it and posts to `WKScriptMessageHandler`.
3. `Notifier` receives the message, extracts count, and shows a native `UNUserNotification`.
4. User clicks the notification; `Notifier` selects the service tab and brings the window to front.

## Persistence

- **Profiles and tabs:** `~/Library/Application Support/Tabchat/state.json` holds open tabs, profile names, and user settings (theme, pause state, start-at-login).
- **Sign-in state:** Each profile's `WKWebsiteDataStore` holds cookies, session storage, and site data, persisted by WKWebView.

## Planned but not yet built (v2+)

- Split view (two tabs side by side)
- Tab sleep: unload a tab's WKWebView after idle time to save memory; reload on next use
- Duplicate tab, incognito tab
- Card reorder and hide
- `Cmd+K` quick switcher palette
