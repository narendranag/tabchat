**New: LinkedIn and X for agents.** Local agents can now read your LinkedIn messages and look up LinkedIn and X profiles, read-only. Nothing here types, likes, follows, connects or sends.

- **LinkedIn Messaging:** the conversation list (`chats`, with dates and unread counts; `--since` reaches older conversations) and the open conversation's messages (`messages`, `history`). Each message has a stable id, the sender's profile link, and a full timestamp to the minute where LinkedIn shows one. `open` opens a conversation by name or thread id, which may mark it read; `--if-read` refuses unread ones.
- **Profiles:** `profile --url` reads one `https://www.linkedin.com/in/<slug>` or `https://x.com/<handle>` page: name, headline, bio, location, links, and on X the posts on the first screen. It loads the page in a hidden window that uses the tab's sign-in, so your tabs never move. It allows one profile a minute and never scrolls. LinkedIn's About section is often below the first screen, so its bio may be empty.
- **Your use comes first:** LinkedIn and X actions wait while you're using Tabchat.
- **Clearer failures:** every error now carries a `code`. `checkpoint` and `signed-out` mean stop for the day (CLI exit 3). `rate`, `owner-active`, `busy` and `asleep` mean try later (exit 75). Security-check and captcha pages return `checkpoint` instead of their text.
- WhatsApp and Discord replies are unchanged, except that failures gain `code`.

Details: [`docs/04-agent-api.md`](https://github.com/narendranag/tabchat-for-agents/blob/main/docs/04-agent-api.md). Everything from [0.2.0](https://github.com/narendranag/tabchat-for-agents/releases/tag/v0.2.0) still works. Your services and sign-ins carry over when you replace the app.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon.

**Opening it the first time:** this build is signed with a development certificate but **not notarised**, so macOS blocks a normal double-click on other Macs. Drag Tabchat to Applications, then right-click it → **Open** → **Open**. Or go to System Settings → Privacy & Security → **Open Anyway**.

SHA-256 of `Tabchat-0.3.0.dmg`: `1cace31f1ce61dc83d62b202185773088108cd3bc1bde9e61312cd0831a2b4f7`
