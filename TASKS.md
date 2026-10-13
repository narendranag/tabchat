# Tasks — Tabchat (Mac)

<!-- Format (shared by every brain): one `- [ ]` per task; optional `📅 YYYY-MM-DD` due date and `#tags`.
     Now / Next / Later / Done. Current status is in CLAUDE.md ("Status"); decisions in DECISIONS.md. -->

## Now

- [ ] **Skeleton**: XcodeGen project, `just` recipes, swiftformat/swiftlint, XCTest, Actions CI #mac

## Next

- [ ] **Core**: sidebar, service catalog, custom sites, profiles, persistence, navigation, find, downloads, external links, offline screen #mac
- [ ] **Mac integration**: unread on tabs/Dock/menu bar, notifications → tab, pause, close keeps running, login item, app menu + shortcuts #mac
- [ ] **The rest**: split view, `Cmd+K`, tab sleep, duplicate/incognito, card order, settings window #mac
- [ ] **Packaging**: unsigned `.app`/`.dmg` (Apple Silicon) built locally #mac
- [ ] Docs to the fleet standard (`docs-build --init`) #docs

## Later

- [ ] Signed, notarized `.dmg` from GitHub Actions + Sparkle updates (needs an Apple Developer ID — costs money, Narendra decides)

## Done

- [x] Engine spike: GO (`spike/`) — 2026-10-13
- [x] Linux code to the `Linux` branch, clean `main`, README for building in public — 2026-10-13
- [x] Plan and decisions for the Mac rewrite (`brief/mac-rewrite.md`) — 2026-10-13
