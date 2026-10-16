**Your input, not an agent's.** Tabchat now tells your own keyboard, mouse and trackpad apart from an agent driving its window (UI tests, computer use, cliclick, AppleScript), so agent work no longer makes Tabchat think you're using it.

- **`tabchatInputSecondsAgo`** in `status` counts only your hardware input. It's absent until you have touched Tabchat since launch, as before.
- **New: `agentInputSecondsAgo`** in `status`, the same for synthetic input: a reason for a caller to wait, but not you.
- **`owner-active`** (LinkedIn and X actions) counts only your input, and now carries **`retryAfter`** (seconds until your two minutes end). A `rate` refusal on `profile` carries it too.
- How it tells them apart: hardware events have no source process; anything posted through `CGEvent` carries its poster's pid. Measured on macOS 26; details in the docs.
- Every other call and field is unchanged.

Details: [`docs/04-agent-api.md`](https://github.com/narendranag/tabchat-for-agents/blob/main/docs/04-agent-api.md). Your services and sign-ins carry over when you replace the app.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon.

**Opening it the first time:** this build is signed with a development certificate but **not notarised**, so macOS blocks a normal double-click on other Macs. Drag Tabchat to Applications, then right-click it → **Open** → **Open**. Or go to System Settings → Privacy & Security → **Open Anyway**.

SHA-256 of `Tabchat-0.4.2.dmg`: `b341c03b4eac5c2c4003d097836c1d1e4ace8b6f32601a6bd3ff493d0253ef26`
