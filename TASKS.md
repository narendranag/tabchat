# Tasks — Tabchat (Mac)

<!-- Format (shared by every brain): one `- [ ]` per task; optional `📅 YYYY-MM-DD` due date and `#tags`.
     Now / Next / Later / Done. Current status is in CLAUDE.md ("Status"); decisions in DECISIONS.md. -->

## Now

- [ ] **Engine spike** (`spike/`, throwaway): WKWebView per service; check sign-in persistence, separate accounts, shared Microsoft sign-in, notification shim, Teams/Discord calls and screen share, Brightspace SSO. Go/no-go into `DECISIONS.md` — see `brief/mac-rewrite.md` #mac

## Next

- [ ] **Skeleton**: XcodeGen project, `just` recipes, swiftformat/swiftlint, XCTest, Actions CI; tag `upstream-final` and remove the Electron code from `main` (dashboard first) #mac
- [ ] **Core**: sidebar, service catalog, custom sites, profiles, persistence, navigation, find, downloads, external links, offline screen #mac
- [ ] **Mac integration**: unread on tabs/Dock/menu bar, notifications → tab, pause, close keeps running, login item, app menu + shortcuts #mac
- [ ] **The rest**: split view, `Cmd+K`, tab sleep, duplicate/incognito, card order, settings window #mac
- [ ] **Packaging**: unsigned `.app`/`.dmg` (Apple Silicon) built locally #mac
- [ ] Docs to the fleet standard (`docs-build --init`) and a README crediting MMV2408/tabchat #docs

## Later

- [ ] Signed, notarized `.dmg` from GitHub Actions + Sparkle updates (needs an Apple Developer ID — costs money, Narendra decides)

## Done

- [x] Plan and decisions for the Mac rewrite (`brief/mac-rewrite.md`) — 2026-10-13
