# Tabchat (Mac)

WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace and any website as tabs in one window,
sharing one browser engine. For Narendra, on his Macs.

A fork of [MMV2408/tabchat](https://github.com/MMV2408/tabchat) (MIT, Electron, built for Linux).
Repo: github.com/narendranag/tabchat (public fork). Remotes: `origin` = the fork, `upstream` = MMV2408.
Keep the MIT licence and the credit to the original author.

This brain follows the fleet's standard: how projects are built is in
`~/claude-computer/docs/DEV-GUIDELINES.md`, the tools on the PATH in
`~/claude-computer/claude-global/CLAUDE.md`.

**Resuming:** read `TASKS.md`, then `brief/mac-rewrite.md` (the plan and decisions).

## Status

Planning done (2026-10-13): rewriting from scratch as a native Swift app (macOS 14+, sidebar,
English only). The Electron/Linux code in `src/` is upstream's and will be tagged `upstream-final`
and removed from `main` in the skeleton phase. Next: the WKWebView engine spike.

## Stack

- Swift + SwiftUI/AppKit + WKWebView, macOS 14+, Apple Silicon. Xcode project defined in XcodeGen
  `project.yml`, `just build|run|test`. Uses DEV-GUIDELINES' "Swift for Mac-only apps with deep
  OS hooks" exception.
- Fallback if the spike fails on calls or screen sharing: a clean Electron + TypeScript rewrite.

## Run

Not yet — the Swift project arrives with the skeleton phase. Until then `npm start` runs
upstream's Linux-oriented Electron app.
