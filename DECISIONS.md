# Decisions — Tabchat (Mac)

- [mini] [2026-10-13] Forked MMV2408/tabchat to narendranag/tabchat and set it up as a product in `~/products/tabchat` (not `~/projects`) — Narendra's call; it is an existing, working app being adapted, not a new idea.
- [mini] [2026-10-13] Target: macOS desktop. Stays on Electron until the brain's audit proposes otherwise — it is a fork of an Electron app; DEV-GUIDELINES' Tauri default is the first open decision.
- [mini] [2026-10-13] Rewrite from scratch in Swift + SwiftUI/AppKit + WKWebView instead of refactoring the Electron fork — Mac-only app made of OS hooks (DEV-GUIDELINES' Swift exception); system WebKit keeps memory low. Fallback to a clean Electron + TypeScript rewrite if the engine spike fails on calls or screen sharing. Supersedes the "stays on Electron" entry above.
- [mini] [2026-10-13] Minimum macOS 14 Sonoma — `WKWebsiteDataStore(forIdentifier:)` gives each sign-in its own persistent store.
- [mini] [2026-10-13] Keep the repo `narendranag/tabchat` and the name Tabchat; tag the Linux code `upstream-final` and remove it from `main`; credit MMV2408/tabchat (MIT) in the README.
- [mini] [2026-10-13] Sidebar of service icons rather than a title-bar tab strip; English only; Apple Silicon only.
- [mini] [2026-10-13] Forked Linux code kept on the `Linux` branch (and tag `upstream-final`, both at upstream's 8d5f9c2); `main` holds only the Mac rewrite. Built in public: README, TASKS and DECISIONS kept current on GitHub.
- [mini] [2026-10-13] Engine spike: GO — Narendra ran the spike and reports it works; Swift + WKWebView confirmed, no Electron fallback. The 2026-10-13 research claim that WebRTC calls can't work in WKWebView on macOS was not borne out.
- [mini] [2026-10-13] Reddit and X added to the built-in catalog. iMessage skipped: it has no web version, Apple doesn't allow embedding another app's window, and Messages.app already has its own Dock badge.
- [mini] [2026-10-13] Local builds sign with the free Apple Development identity (Personal Team 4HL2424MH6) instead of ad-hoc — a stable signature stops Keychain re-prompting for WebKit's WebCrypto master key after every rebuild. CI stays ad-hoc via `TABCHAT_SIGN_IDENTITY=-`.
