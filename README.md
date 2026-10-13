# Tabchat for Mac

WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace and any website in one Mac window,
in a sidebar, sharing the system's own web engine.

**Status: early, built in public.** Nothing to download yet. This README, [`TASKS.md`](TASKS.md)
and [`DECISIONS.md`](DECISIONS.md) are kept up to date as the work goes; the full plan is in
[`brief/mac-rewrite.md`](brief/mac-rewrite.md).

## Where this comes from

Tabchat started as [MMV2408/tabchat](https://github.com/MMV2408/tabchat) by Mike Vijverberg: an
Electron app for Linux (MIT). This fork is a from-scratch rewrite as a native macOS app. It
keeps the idea, the name and the feature list, not the code.

The Linux code as it was forked lives on the [`Linux`](https://github.com/narendranag/tabchat/tree/Linux) branch (tag
`upstream-final`). For Linux, use [the original](https://github.com/MMV2408/tabchat).

## What it will do

- Each service in a sidebar: WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, and your own sites
- Several accounts of the same service, each with its own sign-in; one Microsoft sign-in shared
  by Teams, Outlook and OneDrive
- Unread counts on each service, on the Dock icon and in the menu bar
- Native notifications that respect Focus; clicking one opens the right service
- Keeps running in the menu bar when the window is closed; optional start at login
- Pause notifications for an hour, until tomorrow, or until you turn it back on
- Find on page, downloads, back/forward/reload, light and dark mode
- Later: split view, a `Cmd+K` quick switcher, sleeping services to save memory

## How it's built

- Swift, SwiftUI and AppKit, with `WKWebView`: the same engine as Safari, so the app itself stays
  a few megabytes and doesn't bundle a browser
- macOS 14 Sonoma or later, Apple Silicon
- Each account gets its own `WKWebsiteDataStore`, so sign-ins stay separate and survive restarts

## Roadmap

1. **Engine spike** (now): a throwaway app that checks every service works in `WKWebView`,
   including calls and screen sharing in Teams and Discord. If it doesn't, the fallback is a
   clean Electron rewrite.
2. Skeleton: Xcode project, build and test commands, CI
3. Core: sidebar, services, accounts, navigation, find, downloads
4. Mac integration: unread badges, notifications, menu bar, login item, shortcuts
5. Split view, quick switcher, sleeping services, settings
6. A `.dmg` you can download

## License

MIT, see [LICENSE](LICENSE). Original work © Mike Vijverberg.
