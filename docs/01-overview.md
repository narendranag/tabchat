---
id: overview
title: Overview
order: 1
summary: "What Tabchat is, the ideas behind it, and what is in and out of scope."
status: design
updated: 2026-10-13
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

**Credit:** Tabchat is a rewrite from scratch of [MMV2408/tabchat](https://github.com/MMV2408/tabchat), an Electron app for Linux (MIT License, © Mike Vijverberg). This fork is macOS-only; the original Linux code lives on the [`Linux`](https://github.com/narendranag/tabchat/tree/Linux) branch (tag `upstream-final`).

## The ideas behind it

1. **One app, not context-switching:** Bring all your messaging and work apps into one place instead of Alt-Tab between browsers and standalone apps.
2. **Native and lightweight:** Built in Swift with macOS system frameworks (SwiftUI, AppKit, WKWebView), not a bundled browser. The app itself is a few megabytes; all the heavy lifting is the web service.
3. **Unified notifications:** Notifications arrive in one place, respect your Focus modes, and clicking one opens the right service in the window instead of a new window or tab.
4. **Deep macOS integration:** The app lives in the menu bar when closed, updates Dock and menu bar badges, supports start-at-login via `SMAppService`, uses system theme (light/dark).

## Scope: v1 features

- Sidebar of service icons, icon badges for unread
- Services: WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, custom sites
- Multiple accounts per service, each with its own sign-in; Teams, Outlook (work), OneDrive and Brightspace share one Microsoft sign-in by default
- One WKWebsiteDataStore per sign-in; sign-ins survive restart
- Unread counts in Dock badge and menu bar dot
- Native notifications via UNUserNotificationCenter; respects Focus; clicking opens the service
- Menu bar icon; app closes to menu bar, optional start-at-login
- Pause notifications (1 hour, until tomorrow 08:00, until off)
- Find on page, downloads, back/forward/reload/home buttons
- Light/dark mode following the system

## Out of scope (v1)

- Split view, `Cmd+K` quick switcher, tab sleep, duplicate/incognito tabs, card reorder/hide
- Linux packaging, GNOME D-Bus integration
- Upstream updater, Sparkle, donate/what's new screens

## What stays hard

1. **WebRTC in WKWebView on macOS:** Teams and Discord calls, and Teams screen share. The engine spike confirmed these work, but edge cases (mute, camera, screen content) may need workarounds.
2. **School SSO for Brightspace:** Some institutions use OIDC or SAML flows that might not survive `WKWebsiteDataStore` boundaries.
3. **Unread detection:** Each service reports unread differently—count in tab title `(3) …`, favicon, or hidden DOM. Hardcoded CSS selectors and JS injection per service.
