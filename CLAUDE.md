# TabChat for Agents

WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace and any website as tabs in one window,
sharing one browser engine — and readable by local AI agents through a socket, the `tabchat-agent`
CLI and MCP (read tier and actions tier; drafts, and sends only after Narendra clicks Send in Tabchat). For Narendra, on his Macs. Renamed from
"Tabchat (Mac)" on 2026-10-15; the app and bundle id (`com.narendranag.tabchat`) keep the old
name so sign-ins survive; the repo became `narendranag/tabchat-for-agents` (GitHub redirects old links). It is an independent community port of MMV2408/tabchat
(Mike asked for that line in the README).

A from-scratch native rewrite of [MMV2408/tabchat](https://github.com/MMV2408/tabchat) (MIT,
Electron, Linux). Repo: github.com/narendranag/tabchat-for-agents (renamed from `narendranag/tabchat` 2026-10-15; public fork, built in public — keep the
README, `TASKS.md` and `DECISIONS.md` current). Remotes: `origin` = the fork, `upstream` = MMV2408.
The forked Linux code is on the `Linux` branch (tag `upstream-final`); `main` holds only the Mac app.
Keep the MIT licence and the credit to the original author.

This brain follows the fleet's standard: how projects are built is in
`~/claude-computer/docs/DEV-GUIDELINES.md`, the tools on the PATH in
`~/claude-computer/claude-global/CLAUDE.md`.

**Resuming:** read `TASKS.md`, then `brief/agent-api.md` (the agent API) and `brief/mac-rewrite.md`
(the app). Never commit chat content, contact names or numbers: the repo is public.

## Status

**v0.3.0 released** (2026-10-16, LinkedIn readers and profiles for the CRM; v0.2.0 2026-10-15, the agent API). **Paused** at Narendra's word
on 2026-10-15; pick up from `TASKS.md`. A from-scratch native Swift
app (macOS 14+, Apple Silicon, sidebar, English only); all six phases of `brief/mac-rewrite.md` are
built. Upstream's Linux code is on the `Linux` branch; `main` holds only the Mac app. CI (lint →
test → build on `macos-26`, Xcode 26.6) runs on every push. Upstream was told
(MMV2408/tabchat#1, since deleted; Mike kept the name and asked for the "independent community
port" line). **Agent API** (`docs/04-agent-api.md`): read and act tiers, drafts and confirmed sends on
WhatsApp, read-only Discord, LinkedIn as a tab; complements the CRM's plan
(`~/marain/crm/docs/10-relationship-manager.md`, final). Check with the CRM session before restarting
Tabchat: its nightly run uses it. Open items are in `TASKS.md`; what's left overall is in the
README's "Still to do".

## Stack

- Swift + SwiftUI/AppKit + WKWebView, macOS 14+, Apple Silicon. Xcode project defined in XcodeGen
  `project.yml`, `just build|run|test`. Uses DEV-GUIDELINES' "Swift for Mac-only apps with deep
  OS hooks" exception.
- Local builds sign with the free Apple Development identity (team 4HL2424MH6) so Keychain keeps
  trusting WebKit's WebCrypto key across rebuilds; CI signs ad-hoc (`TABCHAT_SIGN_IDENTITY=-`).
- `gh` defaults to `narendranag/tabchat-for-agents` in this clone (it had picked upstream); pass `-R` anyway.

## Release

Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`, `just dmg`, write
`brief/release-<version>.md`, then tag `v<version>` and `gh release create … --notes-file …`.
Publishing is Narendra's call.

## Run

```sh
just gen     # xcodegen → Tabchat.xcodeproj (generated, not committed)
just lint    # swiftformat --lint + swiftlint --strict
just test    # XCTest
just run     # build and open
```

Details: `docs/03-building.md`. First run on a new Mac needs `sudo xcodebuild -runFirstLaunch`
(Narendra, in Terminal.app). The throwaway spike is in git history (commit 520499b).
