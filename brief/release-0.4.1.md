**New: teacher feedback on ManageBac.** Local agents can now read the teacher's annotations on a submitted file: the marks behind a task's "View Teacher Feedback" button.

- **`feedback --path /document_previews/modal/<token>`** opens ManageBac's own document viewer read-only, with auto-save off, in a hidden window that shares the tab's sign-in. It returns every annotation: page, type (highlight, ink, note, text box…), position, the comment text, the words under a highlight, author, dates and any comment replies. Nothing is ever written back.
- **`feedback --save`** also saves the annotated PDF to `~/Downloads/Tabchat/managebac/`, quarantined.
- **Same careful limits:** each call counts as two requests (three with `--save`) against the 40-an-hour budget, with the same pacing and stops as `get`. `get` may read that one viewer path outside `/parent`.
- MCP: `tabchat_feedback`.

Details: [`docs/04-agent-api.md`](https://github.com/narendranag/tabchat-for-agents/blob/main/docs/04-agent-api.md). Everything from [0.4.0](https://github.com/narendranag/tabchat-for-agents/releases/tag/v0.4.0) still works. Your services and sign-ins carry over when you replace the app.

**Requirements:** macOS 14 Sonoma or later, Apple Silicon.

**Opening it the first time:** this build is signed with a development certificate but **not notarised**, so macOS blocks a normal double-click on other Macs. Drag Tabchat to Applications, then right-click it → **Open** → **Open**. Or go to System Settings → Privacy & Security → **Open Anyway**.

SHA-256 of `Tabchat-0.4.1.dmg`: `4729f70bbce26aead954c4b1cdfbbe5b517bafef697d99bf75b53c8e132009c0`
