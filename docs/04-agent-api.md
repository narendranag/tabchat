---
id: agent-api
title: Agent API
order: 4
summary: "How local agents read chats and act in TabChat: the socket, the CLI and MCP, the read and act tiers, the WhatsApp scripts, and the security model."
status: provisional
updated: 2026-10-16
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
| `chats` | read | `tab` (WhatsApp, Discord, LinkedIn); optional `readOnly`, `since` (act) | chat list with `unread` and `date`; `countsOnly` gives numbers only; `since` scrolls the list |
| `messages` | read | `tab` (WhatsApp, Discord, LinkedIn) | open chat: id, direction, sender, stamp, time, day, date, text, document, media, rendered; LinkedIn adds `profile`, `precision`, and `key`, `chatProfile` on the response |
| `page` | read | `tab` | url, title, visible text (≤20,000 characters) |
| `open` | act | `tab`, `chat`, optional `ifRead` | opens the chat with that exact name, from the list or through search |
| `contact` | act | `tab` | name, phone, about of the open chat |
| `download` | act | `tab`, `message` | `file: {path, bytes}` for the saved document, photo or video |
| `draft` | act | `tab`, `text`, optional `chat` | types the message into the chat's box and stops |
| `send` | act | `tab`, `text`, optional `chat` | sends one message after the owner clicks Send in Tabchat |
| `history` | act | `tab`, optional `screens` (1–20, default 3), `until` | messages read while scrolling back and down again; with `until`, only newer ones, and `reached` says whether it got there |
| `profile` | act | `tab` (LinkedIn or X), `url` | `profile`: name, headline, bio, location, links, X `posts`, text; one a minute |
| `get` | read | `tab` (ManageBac), `path`, optional `save` | `fetched`: url, status, contentType, title, text, html; with `save`, `file`: path, bytes, name, contentType |
| `inspect` | debug | `tab`, `selector` | element structure (debug builds only) |

Every failure carries a `code`: `checkpoint` or `signed-out` (stop for the day; the CLI exits 3),
`rate`, `owner-active`, `busy` or `asleep` (try later; exit 75), `refused`, `not-found` or `failed`
(exit 1).

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

## LinkedIn readers

Read only (`App/Agent/LinkedInScripts.swift`, `AgentService+LinkedIn.swift`): nothing types, likes,
connects or sends. Asked for by the CRM (2026-10-16) so it can drop its Chrome-bridge reads.
Written against LinkedIn's `msg-*` classes (checked live 2026-10-16):

- `chats`: `.msg-conversations-container__conversations-list li.msg-conversation-listitem`; name from
  `…__participant-names`, preview `.msg-conversation-card__message-snippet`, `time`, unread from the
  badge count or a `--unread` class. `date` is ISO (`2026-10-14`), from "3:04 PM" (today), "Yesterday",
  weekday names (the last week), "Oct 14" (this year, or last when that is ahead) and "Oct 14, 2025".
  **The rows carry no thread link or profile link**: `key` and `profile` are absent from `chats`
  and come from `open` and `messages`. `chats --since` scrolls the list (actions tier).
- `messages`: `.msg-s-message-list-content li.msg-s-message-list__event`; the day heading
  (`…__time-heading`) and the group's sender, `/in/` link and time (`.msg-s-message-group__meta`) carry over
  to follow-on messages; each `.msg-s-event-listitem` has its `data-event-urn` as a stable `id`;
  direction from `--other`. `stamp` is a full ISO time with the local offset when the page gives a day
  and a time (`precision: "minute"`), else only `date` (`precision: "day"`). The response carries
  `key` (from `/messaging/thread/<id>/`) and `chatProfile` (the header's `/in/` link). The header's name
  is its `h2`, read selector by selector (a selector list returns the profile link, name and
  headline together, first).
- `open --chat NAME|THREAD-ID [--if-read]` clicks the row (scrolling the list to find it); a thread id
  not in the list loads its address in the tab. It may mark the thread read. `history` scrolls the
  thread up `screens` screens, reads, and scrolls back down; `--until` as for WhatsApp.
- `open`, `history`, `chats --since` and `profile` refuse with `owner-active` while the owner has
  used Tabchat (in front) in the last two minutes.
- A checkpoint, authwall or captcha page gives `code: "checkpoint"`; a sign-in page `signed-out`.
- Live-checked 2026-10-16: `chats` (13 rows), `chats --since` (38 rows over 3½ weeks, 5.7 s),
  `messages` (ids, profiles, minute stamps), `history`, `open --chat NAME --if-read`, `owner-active`
  and `rate`. Not yet live: `open` by thread id.

## Profiles

`profile --tab ID --url URL` (`App/Agent/ProfileReader.swift`) takes only
`https://www.linkedin.com/in/<slug>` and `https://x.com/<handle>` (normalised; anything else is
`refused`), and the LinkedIn or X tab whose sign-in to use, with actions ticked. It loads the page in a
**hidden web view** sharing that tab's website data store, in an off-screen window that is never
shown, so the owner's tab never moves and need not be awake. It waits up to 15 seconds for the profile
to draw and reads the first screen without scrolling. LinkedIn has two profile layouts: the newer
one (seen 2026-10-16) is built from `componentkey` cards, the name an `h2` in the `…Topcard` card,
the headline the first paragraph after it, the location the paragraph beside "Contact info"; the
older one has `main h1`, `.text-body-medium` and `.text-body-small` in the top card's section. Both
are read; external links have LinkedIn's `/redir/redirect` unwrapped. `bio` (the About section) is
often empty: LinkedIn draws it lazily below the first screen, and `profile` doesn't scroll. X: X's `UserName`, `UserDescription`, `UserLocation`, `UserUrl` and the
`article[data-testid="tweet"]` posts on screen (url, ISO time, text, `pinned`/`repost`). One load a
minute (`rate`); X `/account/access`, Arkose or captcha frames, or "unusual activity" without a
profile give `checkpoint`; "doesn't exist" or "suspended" give `not-found`. The page's timers run
slowly in a window that is never shown, so the waiting is done in Swift (a `probe` script every
250 ms, each script run with a deadline), not in the page. Live-checked 2026-10-16 on the owner's own
profiles: X in 2.2 s (four posts), LinkedIn in 1.2 s (name, headline, location).

## ManageBac

Read only, and the one reader that makes requests of its own (`App/Agent/ManageBac.swift`,
`AgentService+ManageBac.swift`). The owner asked for it on 2026-10-16 for the school brain's sync
(08:00 and 16:30 IST on mini), knowing ManageBac's terms forbid automated access; so the limits are
Tabchat's, not the caller's:

- **Service:** `managebac`, built in, asks for the school's address (`https://<school>.managebac.com`),
  its own sign-in, stays loaded. The repo never holds a school's address.
- **`get --tab ID --path PATH`** (read tier): one `fetch(path, {method: "GET", credentials: "include"})`
  run in the tab's agent world, so the visible tab never moves and it works off screen. Only the tab's
  own `https://<school>.managebac.com` origin; pages only under `/parent`; no `..`, no sign-out paths.
  Returns `fetched`: the URL it ended at, status, content type, title, the text (scripts and styles
  removed, one line per block, ≤ 50,000 characters) and the HTML (≤ 1.5 MB) for the caller to parse.
- **`get --save`**: one file through the tab's own download machinery (`startDownload`, its cookies):
  a path on the school's site, or a signed link on ManageBac's own storage, which is where class
  materials point (`https://cdn.<region>.managebac.com/uploads/…`, `https://managebac-*.s3.*.amazonaws.com/…`).
  Web pages and files over 25 MB are refused before anything is written; an expired storage link
  (400 or 403 from storage) fails alone without stopping the run. Saved to
  `~/Downloads/Tabchat/managebac/`, quarantined.
- **Pace and budget** (`ManageBac.Gate`): one request at a time (`busy`), 2–5 s apart with jitter
  (Tabchat waits), at most 40 in any hour (`rate`).
- **Stops:** a sign-in page (by path, another host, a password form outside `/parent`) or a 401 gives
  `signed-out` with an error starting `loggedOut:`; a 403, 429, Cloudflare challenge, 5xx or network
  error gives `checkpoint`. Either stops every ManageBac request for an hour, with a toast in Tabchat.
  No retries.
- **Kill switch:** unticking the tab in Settings → Agents refuses everything at once.
- Nothing in the actions tier: ManageBac has no `open`, `download`, `draft` or `send`.
- Live-checked 2026-10-16: `/parent`, notifications, a class, a task, a unit and a class stream
  (0.5–3 s each with the pacing), and a `.docx` saved from the CDN. `/parent/notifications` holds no
  items: the bell's notifications come from a separate Faria service on another host, which `get`
  does not reach; the class streams carry the same posts and files.

## Live checks

Run against the debug build, with the services ticked in Settings → Agents:

```sh
TA=build/DerivedData/Build/Products/Debug/Tabchat.app/Contents/MacOS/tabchat-agent
$TA tabs
$TA chats --tab <id> --counts-only
$TA inspect --tab <id> --selector '#main'
```

Never paste real chat content, names or numbers into the repo, tests or issues.
