# TabChat for Agents

Your chat apps in one Mac window — WhatsApp, Discord, Teams, Outlook, GitHub and any website —
**and readable by the AI agents on your Mac**. Ask Claude Code (or any local agent) what came in on
WhatsApp, to pull the PDFs a contact sent you, or to update your CRM with a contact's number.
Nothing leaves your Mac except through the agents you run, and nothing is sent from your accounts
unless you click Send yourself.

TabChat for Agents is an independent community port of [MMV2408/tabchat](https://github.com/MMV2408/tabchat);
it is not affiliated with or endorsed by the original project.

**Status: working, built in public.** The Mac app is v0.1.1; the agent API is new (October 2026) and
tested live on WhatsApp. [`TASKS.md`](TASKS.md) and [`DECISIONS.md`](DECISIONS.md) are kept up to date;
the reasoning behind the agent API — what can be read, the risks per service, the security model — is in
[`brief/agent-api.md`](brief/agent-api.md).

## Why

Every chat service keeps its messages behind its own app. The official APIs either don't exist for
personal accounts (WhatsApp), forbid automating a user account (Discord), or need an admin to approve
them (Teams). The unofficial clients that do give access re-implement the protocol, and that is what
gets accounts banned.

TabChat takes the other road: it runs each service's **own web client**, signed in by you, and lets
agents read what that page already shows. To the service it looks like you looking at the window.

## What agents can do

Off by default. In **Settings → Agents** you switch agent access on and tick, per service, what
agents may read and whether they may also act.

| Call | Tier | What it does |
| --- | --- | --- |
| `tabs` | read | The services you opened to agents, with unread counts |
| `feed` | read | Notifications received (sender and text), kept in memory only, at most 24 hours |
| `chats` | read | The chat list on screen: name, last message, time, unread |
| `messages` | read | The messages of the open chat: sender, time, text, attached documents |
| `page` | read | The visible text of whatever page a service shows (any site) |
| `open` | act | Open a chat by its exact name (searching for it if it's far down the list) |
| `contact` | act | The open chat's name, phone number and "About" |
| `download` | act | Download a document, photo or video from a message to `~/Downloads/Tabchat/<service>/<contact>/` |
| `history` | act | Scroll the open chat back and read earlier messages |
| `draft` | act | Type a message into a chat and stop there; you send it when you want |
| `send` | act | Send one urgent message, after you click Send in Tabchat's own dialog |

Reading works on every service through `page`; the chat-aware calls and the actions are WhatsApp
only so far. **Agents never send on their own:** a draft waits for your Return, and `send` waits for
your click in a Tabchat dialog showing the recipient and the whole message. One message at a time,
never bulk or scheduled. Opening a chat marks it read, and the sender sees that.

### Using it

The app ships a command-line tool, `tabchat-agent`, that talks to the running app over a Unix socket:

```sh
TA=/Applications/Tabchat.app/Contents/MacOS/tabchat-agent
$TA tabs
$TA messages --tab <id>
$TA download --tab <id> --message <message-id>
```

The same calls are MCP tools: `tabchat_tabs`, `tabchat_feed`, `tabchat_chats`, `tabchat_page`, `tabchat_messages`, and the actions `tabchat_open`, `tabchat_contact`, `tabchat_download`, `tabchat_draft`, `tabchat_send`, `tabchat_history`.
Register it once in Claude Code:

```sh
claude mcp add --scope user tabchat -- /Applications/Tabchat.app/Contents/MacOS/tabchat-agent mcp
```

### Safety

- **Your Mac only.** A Unix socket readable and writable by your user alone — no network port, so no
  web page can reach it. Any program running as you can use it, so tick only what you mean to share.
- **Logged.** Every call — which program, which service, how many items, the outcome — never the content.
  Settings → Agents → Show Call Log.
- **Isolated.** The readers run in their own WebKit content world: the page's scripts can't see them.
  Read calls make no clicks and no requests of their own.
- **Untrusted text.** Anything a chat returns was written by other people and may carry instructions
  aimed at your agent. Responses are labelled `untrusted`; an agent reading your chats should not
  also hold tools that publish.
- **Terms of service.** Every service's terms forbid "automated access" in broad words. Reading in the
  official client is the lowest-risk way there is; automated sending is what gets WhatsApp and Discord
  accounts banned, which is why there is none. Work accounts (Teams, Outlook) are subject to your
  employer's policies. Details per service in [`brief/agent-api.md`](brief/agent-api.md).

## The app

- Each service in a sidebar; several accounts per service, each with its own sign-in; one Microsoft
  sign-in shared by Teams, Outlook and OneDrive
- Unread counts per service, on the Dock icon and in the menu bar
- Native notifications that respect Focus; clicking one opens the right service; pause and mute
- Keeps running in the menu bar when the window is closed; optional start at login
- Find on page, downloads, split view, a `Cmd+K` quick switcher, sleeping services to save memory
- Built in: WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace, Reddit, X, GitHub — or any site

Swift, SwiftUI and AppKit with `WKWebView` — Safari's engine, so the app stays a few megabytes.
macOS 14 Sonoma or later, Apple Silicon.

## Download

Get the latest `Tabchat-<version>.dmg` from [Releases](https://github.com/narendranag/tabchat-for-agents/releases/latest).
v0.1.1 is the app without the agent API; the next release will include it.

The build is **not notarised** yet: the first time, drag it to Applications, then right-click it →
**Open** → **Open** (or System Settings → Privacy & Security → **Open Anyway**).

## Where this comes from

It started as [MMV2408/tabchat](https://github.com/MMV2408/tabchat) by Mike Vijverberg, an Electron app
for Linux (MIT). This is a from-scratch native rewrite for macOS: it kept the idea and the feature list,
not the code, and then grew the agent API. The Linux code as it was forked is on the
[`Linux`](https://github.com/narendranag/tabchat-for-agents/tree/Linux) branch (tag `upstream-final`); for Linux,
use [the original](https://github.com/MMV2408/tabchat).

## Still to do

- **More services for agents**: chat lists, messages and actions for Discord, Teams and Outlook
  (they are readable through `page` today)
- **Videos and albums**: downloads save documents and photos; videos are unchecked and an album gives its first photo
- **Notarised build** and automatic updates (needs a paid Apple Developer ID)
- **Unread for every service**: Reddit and GitHub don't put a count in their page titles
- **Intel Macs**: Apple Silicon only for now

Not planned: sending without your click, bulk or scheduled sending, and iMessage (no web version).

## Building

```sh
brew install xcodegen swiftlint swiftformat just
just run        # build and open
just test       # unit tests, including the agent API against made-up pages
just dmg        # build/Tabchat-<version>.dmg
```

Needs macOS 14+, Apple Silicon and Xcode 26 or later. Without an Apple Development certificate,
use `TABCHAT_SIGN_IDENTITY=- just run`. More in [`docs/03-building.md`](docs/03-building.md);
the agent API's design is in [`docs/04-agent-api.md`](docs/04-agent-api.md).

## License

MIT, see [LICENSE](LICENSE). Original work © Mike Vijverberg.
