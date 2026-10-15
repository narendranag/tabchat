# Brief — an agent API for Tabchat

Exploration, 2026-10-15. **Status: approach agreed 2026-10-15** ("Decided", end of this file);
the smallest proof is being built on branch `agent-api`. This repo is public: the API, its tests and its fixtures never contain real
chat content, contact names, numbers or tokens.

**The question.** Can local agents (Claude Code sessions, other agents on Narendra's Macs) read the
chats in Tabchat's tabs (WhatsApp, Discord, Teams, Outlook and the rest), how, at what risk, and
should they ever send?

## Recommendation in one paragraph

Build a **read-only** API inside the app, **off by default**, reachable only through a **Unix socket**
owned by Narendra's user, with a **CLI** (`tabchat-agent`) that also runs as an **MCP server**
(`tabchat-agent mcp`). It reads what the owner's own signed-in page already has on screen, with a
script in an **isolated WebKit content world**, plus the **notification feed** the app already
receives. It makes no network requests of its own, never clicks, scrolls or opens a chat, so to
WhatsApp or Discord it looks exactly like Narendra looking at the window. Each agent gets a token
scoped to named tabs; every read is logged (who, which tab, how many items — never content).
**No sending.** At most, later, "draft": the agent puts text into the compose box and Narendra
presses Enter. For Outlook and Teams on the work account, Microsoft Graph is the sanctioned route and
may be better than Tabchat; the API's real value is WhatsApp and Discord, where the only
alternatives are unofficial clients that do get accounts banned.

The smallest proof that settles it is two steps (see "Smallest proof"): the notification feed over
the socket (no new contact with any service), then a WhatsApp chat-list reader against a made-up
fixture and one live check by Narendra.

## What there is to read

### Four ways in

| Route | What it gives | Side effects the service can see | Fragility | Verdict |
| --- | --- | --- | --- | --- |
| **A. Notification feed** — the bridge already shims `window.Notification` and forwards title + body to `AppModel.postNotification` | Every incoming message the site chooses to notify: sender (or chat) and preview, per tab, as it arrives | None: the site already calls it | Low; it is the web Notification API | **Yes — first** |
| **B. DOM reading** — `callAsyncJavaScript(_:arguments:in:contentWorld:)` in a named `WKContentWorld` | What is rendered: the chat list (names, last-message preview, time, unread), the open conversation's visible messages, Outlook's message list | None if it only reads. The page's scripts cannot see an isolated world's globals | Medium: selectors change; lists are virtualised, so only what is on screen (≈15–25 chats, the last screenful of messages) | **Yes — the core** |
| **C. The page's own JS state** — WhatsApp's internal modules (what whatsapp-web.js does with `window.require("WAWebCollections")`), Discord's webpack stores | Every loaded chat and message, without the UI | Must run in the page world, so it is detectable in principle; loading older messages makes real requests | High: internal names change every few weeks; Discord treats store access as client modification | **No**, except as a later experiment for WhatsApp, Narendra's call |
| **D. Stores on disk** — IndexedDB/Cache under `~/Library/WebKit/com.narendranag.tabchat/WebsiteDataStore/<id>/` | In theory, history | None | Very high: WhatsApp encrypts its message store at rest; schemas are private; files are live and locked | **No** |

And the route that bypasses Tabchat:

| **E. The services' own APIs** | Microsoft Graph (`Mail.Read`, `Chat.Read`) for Outlook and Teams; GitHub notifications API; Reddit/X APIs | Sanctioned | Low | **Yes for Outlook/Teams if the tenant allows** — see the ToS section |

### Per service

| Service | Best read route | What B can read | Notes |
| --- | --- | --- | --- |
| WhatsApp | A + B | Chat list: name, last-message preview, time, unread count (`#pane-side`, ARIA rows, `span[title]`). Open chat: messages with `data-pre-plain-text="[time, date] Sender: "` | **Opening a chat sends read receipts** to the other person. The reader must never open, click or scroll. Message element ids embed phone numbers — strip them. Multi-device: works without the phone online |
| Discord | A + B | DM and channel list with unread markers; open channel's messages (`li[id^="chat-messages-"]`, `[id^="message-content-"]`) | Using the user token against Discord's REST API is a self-bot (ban). Reading the DOM is not an API call |
| Teams (work) | E (Graph) if allowed, else A + B | Chat list and open chat (`data-tid` attributes, ARIA) | The tenant's IT policy and DLP apply to work data whatever the route |
| Outlook (work, personal) | E (Graph) or B | Message list: Outlook's `role="option"` rows carry an `aria-label` with sender, subject, preview, time, unread — the easiest DOM of all | Graph gives full bodies and search; the DOM only what is listed |
| OneDrive, Brightspace | Not chats | — | Out of scope |
| Reddit, X, GitHub | A (notifications) + their APIs | Notification pages | GitHub's notifications API is the right tool; X and Reddit DMs: notifications only |

Limits shared by every DOM read:

- **Only loaded tabs.** A sleeping tab has no web view (chat tabs don't sleep by default).
- **Only what is rendered.** Virtualised lists hold a screenful. "Read the whole history" would need
  scrolling or opening chats, which changes what Narendra sees and, on WhatsApp, marks messages read.
  The API does not do it.
- **Selectors break.** Each service gets one small reader script and a fixture test. When a reader
  fails it returns `{"ok": false, "reason": "selectors"}`, never a guess.
- **The notification feed misses** muted chats, chats the site doesn't notify for, and messages that
  arrive while the tab is focused (sites skip notifications then). The DOM read covers the rest.
- **The feed lives in memory only** (a bounded ring buffer, e.g. 500 items or 24 h), never on disk —
  so Tabchat doesn't become a second copy of everyone's messages.

## The agent-facing surface

| Option | For | Against |
| --- | --- | --- |
| Local HTTP on `127.0.0.1` | Any language can call it | Every web page in every browser can reach localhost (CSRF, DNS rebinding); needs a token and origin checks to be safe |
| **Unix socket** `~/Library/Application Support/Tabchat/agent.sock`, mode `0600` | Only Narendra's user can connect; no browser can reach it; no port to collide | Needs a client — which is the CLI |
| **CLI** `tabchat-agent` (second target, shipped inside the app bundle) | The fleet's preferred shape ("scripts over prose", CLIs over MCP); scriptable, testable | — |
| **MCP** (`tabchat-agent mcp`, stdio) | Claude Code and other agents discover the tools themselves | One more layer; kept as a thin wrapper over the same socket calls |

**Recommendation:** socket in the app, one CLI binary with an `mcp` subcommand. Calls, read-only:

```
tabchat-agent tabs                         # tabs the token may see: id, name, service, unread
tabchat-agent feed [--tab ID] [--since 1h] # notification feed (route A)
tabchat-agent chats --tab ID               # rendered chat list (route B)
tabchat-agent messages --tab ID            # visible messages of the open chat (route B)
tabchat-agent mcp                          # the same four as MCP tools
```

Every response is JSON and labels chat text as untrusted: `{"source": "whatsapp", "untrusted": true, …}`.

## Security and privacy

- **Off by default.** Settings → Agents: a switch, the list of agent tokens, and per token the tabs it
  may read (tabs, not services: "Discord" yes, "WhatsApp (personal)" no). New tabs are not readable
  until ticked.
- **Auth.** The socket's file permissions keep other users out. A token (`TABCHAT_AGENT_TOKEN`) names
  the agent and limits its tabs. It is not a wall against Narendra's own processes — anything running
  as him can already read WebKit's cookie files — it is consent and attribution. Tokens go in the
  sops store and reach an agent through `secrets exec --only TABCHAT_AGENT_TOKEN`.
- **Logging.** Each call is logged: time, token name, call, tab, item count, ok/error. **Never
  content.** Visible in Settings → Agents, kept 30 days, in Tabchat's Application Support folder.
- **Prompt injection.** Anyone who can message Narendra can put instructions into an agent's context
  through this API. Read-only plus the `untrusted` label limits the damage; the real defence is that
  the API cannot send, and that an agent reading chats should not also hold tools that publish.
- **Indicator.** A small mark in the sidebar while an agent read happened in the last minute, so
  reads are never invisible.
- **Public repo.** Fixtures are invented HTML; tests assert on made-up names ("Ada", "Test Group").
  No screenshots of real chats, ever.

## Terms of service and ban risk

Checked 2026-10-15 (research notes, sources linked). **The main point:** Tabchat runs each
service's *official* web client, signed in by Narendra. Almost all ban evidence for WhatsApp and
Discord comes from protocol re-implementations (whatsmeow, Baileys) or from scripts that use the
user token against the API. Both are visible at the server. A read-only DOM script in the official
client makes no requests of its own. Every service's terms still forbid it broadly ("automated
means", "unauthorized software"), so the risk for reading is about being detected, not about the
wording. For sending, both the wording and the enforcement point at the account.

| Service | Read (DOM, as proposed) | Send (automated) | Wording | Evidence |
| --- | --- | --- | --- | --- |
| **WhatsApp** | Low–medium | **High** | [Terms](https://www.whatsapp.com/legal/terms-of-service): must not "through automated or other means, access, use, copy … or otherwise exploit our Services in impermissible or unauthorized manners", nor "collect information of or about our users in any impermissible or unauthorized manner"; acceptable use bans "bulk messaging, auto-messaging, auto-dialing" and "non-personal use". [Unofficial-apps FAQ](https://faq.whatsapp.com/1217634902127718): unofficial clients → temporary or permanent ban, device linking restricted | Bans in [whatsapp-web.js](https://github.com/wwebjs/whatsapp-web.js/issues/532) follow *sending* (~200 messages, 2021). [whatsmeow #810](https://github.com/tulir/whatsmeow/issues/810) (May 2025): "account may be at risk" and bans even for low-volume, idle-but-connected protocol clients. TeleMessage-linked accounts couldn't link devices Sep 2025–Feb 2026 ([source](https://www.intradyn.com/whatsapp-blocked-linked-device-archiving)). A 2026 beta tests a "use the official WhatsApp Web" warning ([WABetaInfo](https://wabetainfo.com/whatsapp-is-testing-a-safety-warning-for-unofficial-web-clients)) — Tabchat *is* the official web client. The Jan 2026 AI-chatbot ban is in the Business API terms only. The Business/Cloud API cannot read a personal account |
| **Discord** | Medium | **High** | [Support](https://support.discord.com/hc/en-us/articles/115002192352): "Automating normal user accounts (generally called "self-bots") outside of the OAuth2/bot API is forbidden, and can result in an account termination". [Terms](https://discord.com/terms) (Sep 2025): no scraping "by using any robot, spider, crawler, scraper, or other automatic device, process, or software"; no "unauthorized software designed to modify the services" | What gets terminated is token-using self-bots. Client mods (Vencord, BetterDiscord) inject JS daily with no confirmed enforcement unless abused (community claim, not official) |
| **Teams (work)** | Low with Microsoft, **medium with the employer** | Low–medium via Graph | Graph [`GET /chats`](https://learn.microsoft.com/en-us/graph/api/chat-list?view=graph-rest-1.0): delegated `Chat.Read`, work/school only, "personal Microsoft account: Not supported". `Chat.Read` needs no admin consent by default, but many tenants turn user consent off | The real constraint is the employer: IT policy, DLP, conditional access, and sending company data to an AI agent at all |
| **Outlook** | Low | Low via Graph | `Mail.Read` works for both work and personal Microsoft accounts | Graph gives full bodies and search — better than the DOM |
| **X** | Medium | High | [Terms](https://x.com/en/tos): no access "other than through the currently available, published interfaces"; no scraping without written permission | DM API needs a paid tier (unverified) |
| **Reddit** | Medium | Medium | User Agreement (Jul 2026): no collecting data "by any means (automated or otherwise)" except as permitted | Public API access ends March 2027 ([TechCrunch](https://techcrunch.com/2026/09/30/reddit-is-killing-rss-feeds-ending-public-api-access-because-of-ai-bots)) |
| **GitHub** | Low | Low | Notifications REST API with Narendra's own token is sanctioned | — |

**Precedents.** Ferdium, Rambox and Franz (the same pattern as Tabchat) have no ban reports found —
absence of evidence, not proof. [lharries/whatsapp-mcp](https://github.com/lharries/whatsapp-mcp)
(whatsmeow) inherits #810's risk, and its documented problem is security: an MCP prompt-injection
attack that exfiltrated message history ([Invariant Labs](https://invariantlabs.ai/blog/whatsapp-mcp-exploited)).
That is the attack the "no sending, no publishing tools alongside" rule below is for.

**Unverified:** whether WhatsApp Web or Discord detect injected JavaScript in an isolated content
world; a 2023 change to WhatsApp's at-rest encryption (2021 analysis: message text AES-CBC
encrypted in IndexedDB, so route D is out anyway); Microsoft wording specific to DOM reading.

**What keeps the read risk low, as rules for the build:** no network requests from the reader; no
clicks, scrolls, focus changes or opened chats; reads only when an agent asks (no background
polling, no bulk export); isolated content world; one service's reader can be switched off without
a release (a setting).

## Sending

**Not in this work.** Automated sending is the one thing all the evidence points at, for WhatsApp
and Discord especially, and it turns a prompt injection from "the agent read something misleading"
into "the agent wrote to someone as Narendra".

If it is ever wanted, the only shape worth considering is **draft**: the agent asks Tabchat to
put text into the compose box of a chat that is already open, Tabchat shows the tab with a banner
("Draft from <agent> — press Return to send"), and Narendra sends it himself. The network sees a
normal human send. Microsoft and GitHub sending, if wanted, belongs in Graph and `gh`, not here.
A separate decision, after reading has proved itself.

## Smallest proof

Two steps on a branch `agent-api`, each with tests, nothing released:

1. **Feed over the socket** — the in-app socket server, token check, tab scoping, call log, the
   `tabchat-agent` CLI with `tabs` and `feed`, and the MCP wrapper. Data: unread counts and the
   notification feed the app already receives. No new contact with any service. Tests: the request
   handler, scoping and log with made-up tabs and notifications; the ring buffer's bounds.
   *Settles:* is the surface useful to an agent, and is the security model livable.
2. **One DOM reader: WhatsApp's chat list** — the hardest and most valuable service. A reader
   script run in an isolated content world, tested in XCTest against an invented HTML fixture
   ("Ada", "Test Group"), then **one live check by Narendra**: `tabchat-agent chats --tab <id>
   --counts-only` prints how many chats and fields were found, not their content, so nothing
   private lands in a Claude session or the repo.
   *Settles:* does a passive DOM read work on the real page, and how much does it give.

Discord, Teams, Outlook readers and the `messages` call follow only if both steps hold up.

## Decided (Narendra, 2026-10-15)

| Question | Answer |
| --- | --- |
| Approach | Read-only, off by default; Unix socket + `tabchat-agent` CLI with an `mcp` subcommand. No sending of any kind now |
| Microsoft | **DOM readers for all services**, Outlook and Teams included — not Graph. Accepted: medium risk with the employer's IT/DLP policy for work data |
| Prototype | Build both proof steps on branch `agent-api`, in the public repo, off by default, made-up fixtures only; nothing merged or released without Narendra's word |
| Auth | **Socket file permissions only** (`0600`, Narendra's user). No tokens: any process running as Narendra can read every tab that is switched on for agents. Which tabs are readable is set per tab in Settings; the call log records the client's process name instead of a token name |

| Content (later the same day) | Agents see names, previews and messages, not only counts — Narendra wants agents to act on who and what (download a contact's files, update the CRM) |
| Drafts and sending (2026-10-15) | Narendra's call, after the read and act tiers proved out: `draft` types a message and stops; `send` sends one message only after he clicks Send in Tabchat's own sheet (recipient and whole text shown, plain Return does nothing, cancels itself after 5 minutes). Never bulk or scheduled. Supersedes "no sending" below |
| Actions tier | Second per-tab switch, off by default: open a chat, open contact info, download attachments. **Never send.** Opening a chat sends read receipts — accepted. Each action logged and shown in Tabchat |
| Downloads | `~/Downloads/Tabchat/<service>/<contact>/`, quarantined |
| CRM | `~/marain/crm`, written by the agent with that repo's `crm` CLI; Tabchat only hands over name, number and "about" |

Live test, 2026-10-15 (test build on mini): `tabs` scoping, `page` on GitHub and the call log worked;
the WhatsApp chat-list reader, written blind against an invented fixture, read 17 of 17 rendered chats
with name, preview and time on the first try (one 116 badge is a muted chat, which WhatsApp leaves
out of the title count). One bug found live and fixed: accepted sockets inherited non-blocking mode.

Actions tier, live 2026-10-15: `open` opened a named chat from the chat list; `messages` read 8
messages (direction, sender, time, text, document names; scrolled-out ones marked `rendered: false`);
`contact` read name and phone and closed the panel again; `download` scrolled a document into view,
opened WhatsApp's viewer, pressed Download and closed it — a 4-page PDF landed in
`~/Downloads/Tabchat/whatsapp/<contact>/`, quarantined. Selectors were learned with a debug-only
`inspect` call (structure, not content) and are WhatsApp's `data-testid` hooks. Found live and fixed:
the `message-in/out` classes are gone (direction now comes from the status tick), and virtualised rows.

What this changes above: the "Auth" bullet's tokens and the sops entry are dropped; the per-tab
switch and the log stay.
