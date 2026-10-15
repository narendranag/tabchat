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
| `status` | read | — | `focused`, `tabchatInputSecondsAgo`, `macIdleSeconds`, `selectedTab`, `sendPending`, tabs with their `actions` switch |
| `feed` | read | optional `tab`, `sinceSeconds` | notifications from readable tabs; WhatsApp items carry `chat` |
| `chats` | read | `tab` (WhatsApp); optional `readOnly`, `since` (act) | chat list with `unread` and `date`; `countsOnly` gives numbers only; `since` scrolls the list |
| `messages` | read | `tab` (WhatsApp) | open chat: id, direction, sender, stamp, time, day, date, text, document, media, rendered |
| `page` | read | `tab` | url, title, visible text (≤20,000 characters) |
| `open` | act | `tab`, `chat`, optional `ifRead` | opens the chat with that exact name, from the list or through search |
| `contact` | act | `tab` | name, phone, about of the open chat |
| `download` | act | `tab`, `message` | `file: {path, bytes}` for the saved document, photo or video |
| `draft` | act | `tab`, `text`, optional `chat` | types the message into the chat's box and stops |
| `send` | act | `tab`, `text`, optional `chat` | sends one message after the owner clicks Send in Tabchat |
| `history` | act | `tab`, optional `screens` (1–20, default 3), `until` | messages read while scrolling back and down again; with `until`, only newer ones, and `reached` says whether it got there |
| `inspect` | debug | `tab`, `selector` | element structure (debug builds only) |

Text from chats is marked `"untrusted": true`. Nothing is sent without the owner: `draft` stops at the
message box, and `send` waits for a click in Tabchat's own sheet.

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
- `open` waits up to ten seconds for WhatsApp to load, then clicks the chat in the list if WhatsApp has drawn it; otherwise it types the name into the
  search box (`chat-list-search-container` in `#side`, a plain text field, never the message box),
  opens the result with exactly that name, and clears the search. Live-checked 2026-10-15.
- `history` stops after 90 seconds with a `note` (a tab not on screen runs its timers slowly).
- `history` scrolls the message list (the nearest scrolling ancestor of the first message) up
  `screens` screens, waiting for WhatsApp to load more, then back down, keeping each message the
  first time it is drawn, placed right after the known message drawn before it (WhatsApp keeps some
  rows drawn while scrolling). When scrolling loads nothing it presses WhatsApp's own "Click here
  to get older messages from your phone" (after a restart WhatsApp keeps only the newest messages);
  it presses nothing else, and ends at the newest message. It is in the actions tier
  because scrolling back makes WhatsApp fetch older messages. Timers are slowed in a tab that isn't on
  screen, so it is quicker with the WhatsApp tab selected.
- `download` closes any viewer still open, then clicks the document thumb, or for a photo or video
  the `image-thumb`, `video-content` or `blob:` image, and presses `Download` in the viewer. It
  checks that the saved file has the document's name (allowing the ` 1` added for a duplicate) and
  answers `ok: false` with the path when it doesn't. Photos are live-checked (`image-thumb`, 2026-10-15).
  An album (`image-album`, labelled "Media album 4 photos") gives one pass per photo it shows: `files`
  lists them, `note` says when it holds more than it shows. For your own media the viewer has no
  Download button; it is the `Download` menu item under the viewer's `Menu`, which opens only on a
  primary pointer press at the button. Only an item named exactly "Download" is pressed. Videos are
  not checked yet.
- WhatsApp stamps text messages with their day but not documents or photos. `day` is the divider
  above the message in the list ("Today", "Friday", "27/09/2026"; English only). `date` comes from
  the stamp, else from `day` (weekday names count back from today), else from the dated messages on
  either side when both are on the same day; otherwise it is absent.
- `draft` and `send` (`App/Agent/WhatsAppCompose.swift`) type into `#main footer [contenteditable]`
  with `insertText`/`insertLineBreak`, never a Return key, after checking the open chat is the one
  named and the box is empty. `send` first shows `AgentSendConfirm`: a sheet on the main window with
  the program, the recipient and the whole message as a bubble; Send needs a click or Cmd+Return
  (plain Return does nothing), and it cancels itself after 5 minutes. Then it clicks
  `button[aria-label="Send"]` and waits for the box to empty. One pending send at a time; at most
  4,000 characters. Live-checked 2026-10-15.
- Names are compared with emoji read back from WhatsApp's `<img alt>`, and a failed search lists
  the names it found. Your own chat is a `message-yourself-row` in search (open it as `<name>` or
  `<name> (You)`); address-book contacts not on WhatsApp (`out-contact-cell`, "Invite") are skipped.
- For the CRM's nightly run (`~/marain/crm/docs/10-relationship-manager.md`, whose plan this API
  follows): `chats --since <ISO time> --read-only` scrolls the chat list (opening nothing) down to
  chats active on or after that day, by day, and keeps those with nothing unread; `open --if-read`
  refuses, before clicking, a chat whose row shows unread messages; `history --until <id>` returns
  only what is newer than the last stored message; `status` lets it back off while the owner is at
  Tabchat or the Mac. WhatsApp Web shows no chat JIDs, so a chat is keyed by name plus message ids.
  Feed items' `is_group` is left out until a reliable marker is found.
- The CLI waits up to 120 seconds for actions, 360 for `send`, 15 for reads.
- Downloads go through the tab's `WKDownload` handling, redirected by an `AgentDownloadSlot` to
  `~/Downloads/Tabchat/<service>/<contact>/`, and are quarantined.

Each script is tested in XCTest against an invented page (`Tests/AgentTests.swift`,
`Tests/AgentActionTests.swift`). When WhatsApp changes its page, a script returns
`{"ok": false, "reason": …}` rather than a guess; fix the selectors with `inspect` in a debug build.

## Discord readers

Read only (`App/Agent/DiscordScripts.swift`); Discord's terms forbid automating a user account, so
there are no Discord actions. Written against attributes Discord keeps while its class names change
(checked live 2026-10-15):

- `chats`: the links `a[href^="/channels/@me/"]` in `nav[aria-label*="Private"]`, labelled
  "<name> (direct message)" or "(group message)", optionally prefixed "unread,"; the channel id
  from the link is `key`, a stable id; `group` from the label; unread from the number badge.
- `messages`: `ol[data-list-id="chat-messages"] li[id^="chat-messages-"]`; the id is the last part;
  the author is `[id^="message-username-"] [data-text]`, carried to follow-on messages; `stamp` is
  `time[datetime]` (ISO) and `date` its local day; text is `[id^="message-content-"]` outside the
  quoted reply (`message-reply-context-`); attachments under `message-accessories-` give `document`
  (file name) or `media`. "Joined" notices have no author. Direction is not shown.

## Live checks

Run against the debug build, with the services ticked in Settings → Agents:

```sh
TA=build/DerivedData/Build/Products/Debug/Tabchat.app/Contents/MacOS/tabchat-agent
$TA tabs
$TA chats --tab <id> --counts-only
$TA inspect --tab <id> --selector '#main'
```

Never paste real chat content, names or numbers into the repo, tests or issues.
