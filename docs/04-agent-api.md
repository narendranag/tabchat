---
id: agent-api
title: Agent API
order: 4
summary: "How local agents read chats and act in TabChat: the socket, the CLI and MCP, the read and act tiers, the WhatsApp scripts, and the security model."
status: provisional
updated: 2026-10-15
audience: [developers, agents]
depends_on: [overview, architecture]
related: [building]
defines: [agent access, read tier, actions tier, call log, feed]
answers:
  - How does an agent talk to TabChat?
  - What can an agent read, and what can it do?
  - How are permissions, logging and untrusted text handled?
  - How are the WhatsApp readers written and tested?
---

# Agent API

The reasoning (routes considered, terms-of-service risk per service, the decisions) is in
`brief/agent-api.md` in the repo root. This page is how it is built.

## Shape

```
agent (Claude Code, a script…)
  │  tabchat-agent <call> …            or   tabchat-agent mcp  (JSON-RPC over stdio)
  ▼
~/Library/Application Support/Tabchat/agent.sock   (mode 0600, peer uid checked)
  │  one JSON request line → one JSON response line
  ▼
AgentSocketServer → AgentService (main actor)
  ├── AgentResponder     who may read what; tabs, feed           (pure, tested)
  ├── AgentFeed          notifications, in memory, ≤500, ≤24 h
  ├── PageReaders        chat list, page text, debug inspect      (isolated content world)
  ├── WhatsAppScripts    messages, open, download, contact
  └── AgentLog           agent.log: time, program, call, tab, items, outcome — never content
```

The wire format (`Shared/AgentProtocol.swift`) and the MCP adapter (`Shared/AgentMCP.swift`) are
compiled into both the app and the `tabchat-agent` tool, which the app bundle carries in
`Contents/MacOS/`.

## Calls

| Call | Tier | Needs | Returns |
| --- | --- | --- | --- |
| `tabs` | read | — | readable tabs: id, name, service, unread, loaded |
| `feed` | read | optional `tab`, `sinceSeconds` | notifications from readable tabs |
| `chats` | read | `tab` (WhatsApp) | chat list; `countsOnly` gives numbers only |
| `messages` | read | `tab` (WhatsApp) | open chat: id, direction, sender, stamp, time, day, date, text, document, media, rendered |
| `page` | read | `tab` | url, title, visible text (≤20,000 characters) |
| `open` | act | `tab`, `chat` | opens the chat with that exact name, from the list or through search |
| `contact` | act | `tab` | name, phone, about of the open chat |
| `download` | act | `tab`, `message` | `file: {path, bytes}` for the saved document, photo or video |
| `history` | act | `tab`, optional `screens` (1–20, default 3) | messages read while scrolling back and down again |
| `inspect` | debug | `tab`, `selector` | element structure (debug builds only) |

Text from chats is marked `"untrusted": true`. There is no call that sends.

## Permissions

- `settings.agentAccess` — the master switch; off by default. Turning it off stops the socket and
  forgets the feed.
- `Tab.agentReadable` — the read tier, per tab. Incognito tabs are never readable.
- `Tab.agentActions` — the actions tier, per tab, only offered for readable tabs.

These keys came without a schema bump, so v0.1.x still opens the state file (it would refuse a newer
version and reset the tabs).

## WhatsApp scripts

Written against WhatsApp Web's `data-testid` hooks, learned with `inspect` on 2026-10-15:
`#pane-side` rows with `cell-frame-title`; `#main` messages as `[data-id]` with `msg-container`,
`msg-meta`, `selectable-text`, `data-pre-plain-text="[time, date] Sender: "`, and
`document-thumb` titled `View "<file>"`; the document viewer `media-viewer-modal` with `Download` and
`Close` buttons; the contact panel `chat-info-drawer`, opened from `conversation-info-header`.

- Direction comes from the status tick in `msg-meta` (the `message-in/out` classes are gone).
- Messages scrolled out of view are drawn as `data-virtualized="true"`; `messages` reports them as
  `rendered: false`; `download` scrolls them into view first.
- `open` clicks the chat in the list if WhatsApp has drawn it; otherwise it types the name into the
  search box (`chat-list-search-container` in `#side`, a plain text field, never the message box),
  opens the result with exactly that name, and clears the search. Live-checked 2026-10-15.
- `history` scrolls the message list (the nearest scrolling ancestor of the first message) up
  `screens` screens, waiting for WhatsApp to load more, then back down, keeping each message the
  first time it is drawn, placed right after the known message drawn before it (WhatsApp keeps some
  rows drawn while scrolling). It only scrolls, and ends at the newest message. It is in the actions tier
  because scrolling back makes WhatsApp fetch older messages. Timers are slowed in a tab that isn't on
  screen, so it is quicker with the WhatsApp tab selected.
- `download` closes any viewer still open, then clicks the document thumb, or for a photo or video
  the `image-thumb`, `video-content` or `blob:` image, and presses `Download` in the viewer. It
  checks that the saved file has the document's name (allowing the ` 1` added for a duplicate) and
  answers `ok: false` with the path when it doesn't. Photos are live-checked (`image-thumb`, 2026-10-15); an album downloads its first photo; videos are not checked yet.
- WhatsApp stamps text messages with their day but not documents or photos. `day` is the divider
  above the message in the list ("Today", "Friday", "27/09/2026"; English only). `date` comes from
  the stamp, else from `day` (weekday names count back from today), else from the dated messages on
  either side when both are on the same day; otherwise it is absent.
- The CLI waits up to 120 seconds for actions (15 for reads).
- Downloads go through the tab's `WKDownload` handling, redirected by an `AgentDownloadSlot` to
  `~/Downloads/Tabchat/<service>/<contact>/`, and are quarantined.

Each script is tested in XCTest against an invented page (`Tests/AgentTests.swift`,
`Tests/AgentActionTests.swift`). When WhatsApp changes its page, a script returns
`{"ok": false, "reason": …}` rather than a guess; fix the selectors with `inspect` in a debug build.

## Live checks

Run against the debug build, with the services ticked in Settings → Agents:

```sh
TA=build/DerivedData/Build/Products/Debug/Tabchat.app/Contents/MacOS/tabchat-agent
$TA tabs
$TA chats --tab <id> --counts-only
$TA inspect --tab <id> --selector '#main'
```

Never paste real chat content, names or numbers into the repo, tests or issues.
