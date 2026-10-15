**New: TabChat for Agents.** Local AI agents on your Mac (Claude Code or any other) can now work with the chats in Tabchat, through a command-line tool and an MCP server built into the app. It's off until you switch it on in **Settings → Agents**, service by service.

- **Read:** unread counts, notifications, the chat list, the open chat's messages (with dates), and the text of any page. Chats and messages work on WhatsApp and Discord.
- **Act** (a second switch per service, WhatsApp only): open a chat by name, even far down the list; read a contact's details; scroll back through older messages; download documents and photos, albums included, to `~/Downloads/Tabchat/<service>/<contact>/`.
- **Drafts and sending:** an agent can type a draft for you to send. It can also send one urgent message, but only after you click **Send** in Tabchat's own dialog, which shows the recipient and the whole message. Plain Return doesn't send, and the dialog cancels itself after 5 minutes. No bulk or scheduled sending, ever.
- **Discord is read-only**, because Discord's terms forbid automating a user account.
- **LinkedIn** is a new built-in service. It opens on Messaging, with its unread count and notifications.
- **Safety:** the agent connection is a socket only your Mac account can use, with no network port. Every call is logged without its content. Chat text is marked as untrusted for agents.

Details: [`docs/04-agent-api.md`](https://github.com/narendranag/tabchat-for-agents/blob/main/docs/04-agent-api.md), and the reasoning in [`brief/agent-api.md`](https://github.com/narendranag/tabchat-for-agents/blob/main/brief/agent-api.md).

Everything from [0.1.1](https://github.com/narendranag/tabchat-for-agents/releases/tag/v0.1.1) is unchanged. Your services and sign-ins carry over when you replace the app.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon.

**Opening it the first time:** this build is signed with a development certificate but **not notarised**, so macOS blocks a normal double-click on other Macs. Drag Tabchat to Applications, then right-click it → **Open** → **Open**. Or go to System Settings → Privacy & Security → **Open Anyway**.

SHA-256 of `Tabchat-0.2.0.dmg`: `2d1e9071aae83e1cbea2cf456fa56ce8fc0bac6dfab0dce42893ba190105aa8c`
