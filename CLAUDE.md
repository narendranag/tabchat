# Tabchat (Mac)

WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace and any website as tabs in one window,
sharing one browser engine. For Narendra, on his Macs.

A from-scratch native rewrite of [MMV2408/tabchat](https://github.com/MMV2408/tabchat) (MIT,
Electron, Linux). Repo: github.com/narendranag/tabchat (public fork, built in public — keep the
README, `TASKS.md` and `DECISIONS.md` current). Remotes: `origin` = the fork, `upstream` = MMV2408.
The forked Linux code is on the `Linux` branch (tag `upstream-final`); `main` holds only the Mac app.
Keep the MIT licence and the credit to the original author.

This brain follows the fleet's standard: how projects are built is in
`~/claude-computer/docs/DEV-GUIDELINES.md`, the tools on the PATH in
`~/claude-computer/claude-global/CLAUDE.md`.

**Resuming:** read `TASKS.md`, then `brief/mac-rewrite.md` (the plan and decisions).

## Status

Planning done (2026-10-13): rewriting from scratch as a native Swift app (macOS 14+, sidebar,
English only). Upstream's Linux code moved to the `Linux` branch; `main` is clean. The WKWebView engine spike
passed (GO); phases 2–5 are built; now: phase 6 (unsigned `.dmg`).

## Stack

- Swift + SwiftUI/AppKit + WKWebView, macOS 14+, Apple Silicon. Xcode project defined in XcodeGen
  `project.yml`, `just build|run|test`. Uses DEV-GUIDELINES' "Swift for Mac-only apps with deep
  OS hooks" exception.
- Fallback if the spike fails on calls or screen sharing: a clean Electron + TypeScript rewrite.

## Run

```sh
just gen     # xcodegen → Tabchat.xcodeproj (generated, not committed)
just lint    # swiftformat --lint + swiftlint --strict
just test    # XCTest
just run     # build and open
```

Details: `docs/03-building.md`. First run on a new Mac needs `sudo xcodebuild -runFirstLaunch`
(Narendra, in Terminal.app). The throwaway spike is in git history (commit 520499b).
