**New: ManageBac, read only.** ManageBac (the IB school platform) is now a built-in service: add it with your school's address and sign in yourself. Local agents can read its parent pages and save the files teachers attach. They can't click, post, submit or mark anything.

- **`get --path /parent/…`** reads one parent page with your own sign-in, from inside the tab, without moving it and even when it isn't on screen. It returns the page's text (one line per block) and its HTML.
- **`get --save`** saves one attachment, from the school's site or ManageBac's own file storage, to `~/Downloads/Tabchat/managebac/`. Files are quarantined, and anything over 25 MB is refused.
- **Careful by design.** ManageBac's terms forbid automated access, so Tabchat itself keeps the reader slow and polite:
  - one request at a time, 2–5 s apart, and at most 40 an hour;
  - it stops for an hour at the first sign-in page, 401, 403, 429, browser check or server error (`signed-out` or `checkpoint`), and never retries;
  - unticking the tab in Settings → Agents stops it at once.
- The bell's notifications come from a separate service that `get` doesn't reach. The class streams carry the same posts and files.

Details: [`docs/04-agent-api.md`](https://github.com/narendranag/tabchat-for-agents/blob/main/docs/04-agent-api.md). Everything from [0.3.0](https://github.com/narendranag/tabchat-for-agents/releases/tag/v0.3.0) still works. Your services and sign-ins carry over when you replace the app.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon.

**Opening it the first time:** this build is signed with a development certificate but **not notarised**, so macOS blocks a normal double-click on other Macs. Drag Tabchat to Applications, then right-click it → **Open** → **Open**. Or go to System Settings → Privacy & Security → **Open Anyway**.

SHA-256 of `Tabchat-0.4.0.dmg`: `21fb14cc7e3b809a508da724680a85634d6885733cdfee0da7693c60d5b2f32b`
