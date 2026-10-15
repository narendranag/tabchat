---
id: overview
title: Overview
order: 1
summary: "What Tabchat is, the ideas behind it, and what is in and out of scope."
status: provisional
updated: 2026-10-15
audience: [everyone]
depends_on: [index]
related: []
defines: []
answers:
  - "What is Tabchat for?"
  - What is deliberately out of scope?
---

# Overview

## What it is

Tabchat is a native macOS app that brings messaging and productivity services—WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, and any website—into one window. Services appear as icons in a sidebar; each can have multiple accounts (e.g., two WhatsApp numbers) with separate sign-ins, except Teams/Outlook/OneDrive which share one Microsoft login.

The app reuses the system's WebKit engine (WKWebView), so it stays lightweight and integrates deeply with macOS: unread badges on the Dock icon and menu bar, native notifications that respect Focus modes, menu bar icon for always-at-hand access, start-at-login support.

**Credit:** Tabchat is a rewrite from scratch of [MMV2408/tabchat](https://github.com/MMV2408/tabchat), an Electron app for Linux (MIT License, © Mike Vijverberg). This fork is macOS-only; the original Linux code lives on the [`Linux`](https://github.com/narendranag/tabchat-for-agents/tree/Linux) branch (tag `upstream-final`).

**TabChat for Agents.** Since October 2026 the project's focus is letting the AI agents on the
owner's Mac read these services and act in them — see [04 Agent API](04-agent-api.md). It is an
independent community port of MMV2408/tabchat, not affiliated with or endorsed by the original project.

## The ideas behind it

1. **One app, not context-switching:** Bring all your messaging and work apps into one place instead of Alt-Tab between browsers and standalone apps.
2. **Native and lightweight:** Built in Swift with macOS system frameworks (SwiftUI, AppKit, WKWebView), not a bundled browser. The app itself is a few megabytes; all the heavy lifting is the web service.
3. **Unified notifications:** Notifications arrive in one place, respect your Focus modes, and clicking one opens the right service in the window instead of a new window or tab.
4. **Deep macOS integration:** The app lives in the menu bar when closed, updates Dock and menu bar badges, supports start-at-login via `SMAppService`, uses system theme (light/dark).
5. **Agents read what you can see:** Agents get the services through the official web clients you are
   signed in to, read-only by default, never sending — the lowest-risk route to chats that have no
   personal-account API.

## What's built (v0.1.1)

- Sidebar of service icons with unread badges; drag to reorder; right-click menu
- Services: WhatsApp, Discord, Teams, Outlook (work and personal), OneDrive, Brightspace, Reddit, X, GitHub, custom sites
- Multiple accounts per service, each with its own sign-in; Teams, Outlook (work), OneDrive and Brightspace share one Microsoft sign-in by default
- One WKWebsiteDataStore per sign-in; sign-ins survive restart
- Unread counts on each tab, the Dock and the menu bar
- Native notifications that respect Focus; clicking one opens its service; pause (1 hour, until tomorrow 08:00, until off) and per-tab mute
- Closing the window keeps everything running; menu bar item; optional start at login, hidden
- Find on page, downloads, back/forward/reload/home, offline screen with retry
- Split view, `Cmd+K` quick switcher, tab sleep, duplicate and incognito tabs
- Hide and reorder catalog cards; choose which browser opens links
- Light/dark mode following the system

## Not built, or not planned

- Not yet: notarised build (Developer ID), Sparkle updates, Intel builds, unread counts for Reddit and GitHub (no count in their titles)
- Not planned: iMessage (no web version; macOS can't embed another app's window); Linux (use the original)

## What stays hard

1. **WebRTC in WKWebView on macOS:** Teams and Discord calls, and Teams screen share. The engine spike confirmed these work, but edge cases (mute, camera, screen content) may need workarounds.
2. **School SSO for Brightspace:** Some institutions use OIDC or SAML flows that might not survive `WKWebsiteDataStore` boundaries.
3. **Unread detection:** Tabchat reads counts from page titles (`(3) …`, or `•` for "something unread"). Services that only show unread in a favicon or the page itself (Reddit, GitHub) would need per-service scripts, which are not built.
