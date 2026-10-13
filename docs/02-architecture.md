---
id: architecture
title: Architecture
order: 2
summary: "System components, data flow, and design decisions."
status: provisional
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

A SwiftUI app with AppKit where SwiftUI falls short (the main window's close behaviour, the web
view container). Every tab is one `WKWebView`; every sign-in is one persistent
`WKWebsiteDataStore`. Decision logic lives in plain types under `App/Model/` so it can be unit
tested without a window.

## Source layout

```
App/
├── TabchatApp.swift         app entry: main Window, Settings scene, MenuBarExtra, AppDelegate
│                            (notification permission and clicks, Dock reopen)
├── Model/                   plain, testable types
│   ├── AppModel(+Features)  the observable model: tabs, selection, unread, split, sleep, Cmd+K
│   ├── AppState, AppSettings, Tab, Profile, Service   what is saved, and the service catalog
│   ├── StateStore           state.json in ~/Library/Application Support/Tabchat (atomic writes,
│   │                        schema v3, migrates v1 and v2)
│   ├── StableUUID           profile name → stable UUID → WKWebsiteDataStore(forIdentifier:)
│   ├── UnreadParser         "(3) …" → 3, "• …" → unread dot
│   ├── NotificationPause    1 hour / until tomorrow 08:00 / until off; stored as an end date
│   ├── SleepClock           which idle tabs to put to sleep
│   ├── SplitState           the two panes, focused side, divider ratio (20–80%)
│   ├── QuickSwitcher        Cmd+K ranking and actions
│   ├── LinkPolicy, LinkTarget, Browsers   where a link opens (in-app, default or chosen browser)
│   ├── CatalogLayout        hidden and reordered cards in the Add service sheet
│   ├── LoginItem            SMAppService.mainApp
│   └── DownloadNaming, IconCandidate, URLInput
├── Web/
│   ├── TabController        one WKWebView and all its delegates: popups for sign-in, camera and
│   │                        microphone, file uploads, downloads, load errors
│   ├── BridgeScript         injected JS: replaces window.Notification and reports title changes;
│   │                        also holds the Safari user-agent constant
│   ├── IconStore            site icons read from the page, cached in Application Support
│   └── NetworkMonitor       retries failed tabs when the network returns
└── Views/
    ├── MainWindow           hides the window instead of closing it (keeps web views attached)
    ├── WebHost              one container holding every tab's web view; only visible ones shown
    ├── RootView, SidebarView, AddServiceSheet, FindBar, SplitOverlay, QuickSwitcherView
    ├── MenuBarContent, MenuState, AppCommands   menu bar extra and the app menus
    └── SettingsView         General, Notifications, Sleep, Links
Tests/                       XCTest, one file per model type (77 tests)
```

## Services, profiles and tabs

- A **service** is a catalog entry: WhatsApp, Discord, Teams, Outlook (work), Outlook (personal),
  OneDrive, Brightspace (asks for the school's address), Reddit, X, GitHub, or a custom website.
- A **profile** is one sign-in, backed by one persistent `WKWebsiteDataStore`. Teams, Outlook
  (work), OneDrive and Brightspace share the "Microsoft (work)" profile by default; "Add another
  account" creates a new profile.
- A **tab** is a service opened in a profile, with its own name, colour, mute and sleep settings.
  Incognito tabs use a non-persistent store and are never saved.

## Why one container

Every tab's web view stays a subview of one container in the main window, and closing the window
only hides it. A web view taken out of its window is throttled by WebKit, which would stop
notifications and unread counts from background tabs. For the same reason all tabs load at
launch; only tabs that are allowed to sleep (not WhatsApp, Discord, Teams or Outlook by default)
are released after the idle time, and a sleeping tab posts no notifications.

## Data flow: a new message

1. The page calls `new Notification(…)`; the injected bridge posts it to the
   `WKScriptMessageHandler`.
2. Unless notifications are paused or the tab is muted, a `UNNotificationRequest` is posted with
   the tab's name as subtitle and a per-tab thread. macOS applies Focus.
3. The page's title changes to "(3) …"; `UnreadParser` updates the tab's badge, the Dock badge
   (the total) and the menu bar icon.
4. Clicking the notification shows the window and selects that tab.

## Persistence

- `~/Library/Application Support/Tabchat/state.json`: tabs, profiles, settings, pause end date,
  split layout, catalog order. Versioned; older files migrate on load.
- `~/Library/WebKit/com.narendranag.tabchat/`: the data stores (cookies, storage) per profile.
- Login keychain: "Tabchat WebCrypto Master Key", created by WebKit; readable across rebuilds
  because local builds keep the same signing identity (see [03 Building](03-building.md)).
