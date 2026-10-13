# Tabchat for Mac

WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace and any website in one Mac window,
in a sidebar, sharing the system's own web engine.

**Status: v0.1.0 runs, built in public.** Every feature below is built and in daily use on the
author's Mac; there's no public download yet (`just dmg` builds one, see
[`docs/03-building.md`](docs/03-building.md)). This README, [`TASKS.md`](TASKS.md)
and [`DECISIONS.md`](DECISIONS.md) are kept up to date as the work goes; the full plan is in
[`brief/mac-rewrite.md`](brief/mac-rewrite.md).

## Where this comes from

Tabchat started as [MMV2408/tabchat](https://github.com/MMV2408/tabchat) by Mike Vijverberg: an
Electron app for Linux (MIT). This fork is a from-scratch rewrite as a native macOS app. It
keeps the idea, the name and the feature list, not the code.

The Linux code as it was forked lives on the [`Linux`](https://github.com/narendranag/tabchat/tree/Linux) branch (tag
`upstream-final`). For Linux, use [the original](https://github.com/MMV2408/tabchat).

## What it does

- Each service in a sidebar: WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, and your own sites
- Several accounts of the same service, each with its own sign-in; one Microsoft sign-in shared
  by Teams, Outlook and OneDrive
- Unread counts on each service, on the Dock icon and in the menu bar
- Native notifications that respect Focus; clicking one opens the right service
- Keeps running in the menu bar when the window is closed; optional start at login
- Pause notifications for an hour, until tomorrow, or until you turn it back on
- Find on page, downloads, back/forward/reload, light and dark mode
- Split view, a `Cmd+K` quick switcher, and sleeping services to save memory
- WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, Reddit, X, or any site you add

## How it's built

- Swift, SwiftUI and AppKit, with `WKWebView`: the same engine as Safari, so the app itself stays
  a few megabytes and doesn't bundle a browser
- macOS 14 Sonoma or later, Apple Silicon
- Each account gets its own `WKWebsiteDataStore`, so sign-ins stay separate and survive restarts

## Roadmap

1. ~~Engine spike~~: every service works in `WKWebView`, calls and screen sharing included
2. ~~Skeleton~~: Xcode project, build and test commands, CI
3. ~~Core~~: sidebar, services, accounts, navigation, find, downloads
4. ~~Mac integration~~: unread badges, notifications, menu bar, login item, shortcuts
5. ~~Split view, quick switcher, sleeping services, settings~~
6. ~~A `.dmg`~~ (`just dmg`), not yet published
7. Next: a public download, then signing and notarisation so it opens anywhere without warnings

## Building

```sh
brew install xcodegen swiftlint swiftformat just
just run        # build and open
just dmg        # build/Tabchat-<version>.dmg
```

Needs macOS 14+, Apple Silicon and Xcode 26 or later. Without an Apple Development certificate,
use `TABCHAT_SIGN_IDENTITY=- just run`. More in [`docs/03-building.md`](docs/03-building.md).

## License

MIT, see [LICENSE](LICENSE). Original work © Mike Vijverberg.
