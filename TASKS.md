# Tasks — TabChat for Agents

<!-- Format (shared by every brain): one `- [ ]` per task; optional `📅 YYYY-MM-DD` due date and `#tags`.
     Now / Next / Later / Done. Current status is in CLAUDE.md ("Status"); decisions in DECISIONS.md. -->

## Now

- [ ] Post the Reddit comment (draft in `brief/reddit-comment.md`, from Narendra's account) #community
- [ ] Install v0.1.1 on air from the release dmg (air was unreachable 2026-10-13; mini done) #mac

## Next

- [ ] Agent API: videos in `download` (no chat with a video tried yet); albums holding more photos than they show #agent-api
- [ ] Agent API: an agent recipe for contact details → `~/marain/crm` via its `crm` CLI (in that brain) #agent-api

- [ ] Delete the `.verify` leftovers from phase 2's test launch (`~/Library/*/com.narendranag.tabchat.verify*`, 129 MB) — Narendra decides #mac

## Later

- [ ] Feed `is_group` for WhatsApp notifications, once a reliable marker is found on the live page (the CRM asked; absent until then) #agent-api

- [ ] Agent API: Discord, Teams, Outlook readers and a `messages` call, if the proof holds #agent-api

- [ ] Unread counts for Reddit and GitHub (per-service script; their titles carry no count) #mac
- [ ] Intel (x86_64) builds, if anyone asks #mac
- [ ] Signed, notarized `.dmg` from GitHub Actions + Sparkle updates (needs an Apple Developer ID — costs money, Narendra decides)

## Done

- [x] LinkedIn as a built-in service (Messaging, own sign-in, stays loaded): unread count from its title live-checked; notifications go to the feed; no message reader (the CRM reads LinkedIn through opencli) — 2026-10-15

- [x] Agent API for the CRM's nightly run: `status`, `chats --since --read-only`, `open --if-read`, `history --until`, feed `chat` — live-checked 2026-10-15

- [x] Agent API: albums download every photo they show (your own media through the viewer's menu); `history` fetches older messages after a restart; `open` waits for WhatsApp to load — live-checked 2026-10-15

- [x] Agent API: `open` reaches your own chat ("<name>" or "<name> (You)") and skips address-book contacts not on WhatsApp — live-checked 2026-10-15

- [x] Agent API: `draft` and `send` (confirm sheet in Tabchat) for WhatsApp; names with emoji; search lists near misses — live-checked 2026-10-15

- [x] Agent API: `open` finds chats far down the list through WhatsApp's search box, and clears it — live-checked 2026-10-15

- [x] Quarantine "empty agent name" is not a bug: the xattr's name field stays empty, but macOS records Tabchat as the agent in the quarantine events database (read back through `quarantineProperties`) — 2026-10-15

- [x] Agent API: dates from WhatsApp's day dividers; photo download live-checked — 2026-10-15

- [x] Fixes from a fleet session's bug report: `download` waits for an old viewer to close (it had saved the previous file again) and checks the saved name; photos and videos; `history` for earlier messages (live-checked); `date` on messages; CLI timeout 120 s for actions; help text — 2026-10-15

- [x] Repo renamed to `narendranag/tabchat-for-agents` with a new description — 2026-10-15
- [x] Pivot to TabChat for Agents: README rewritten, "independent community port" line (Mike's request on MMV2408/tabchat#1), `agent-api` merged to `main` — 2026-10-15

- [x] Agent API actions tier for WhatsApp: `messages`, `open`, `contact`, `download`, live-tested on mini (branch `agent-api`) — 2026-10-15

- [x] Agent API proof: socket, `tabchat-agent tabs|feed|chats|page|mcp`, per-tab switch, call log; live WhatsApp chat list read 17/17 (branch `agent-api`) — 2026-10-15

- [x] Agent API exploration and decisions: `brief/agent-api.md` — 2026-10-15

- [x] v0.1.1 released with GitHub: https://github.com/narendranag/tabchat/releases/tag/v0.1.1 — 2026-10-13
- [x] Told MMV2408 about the Mac version: https://github.com/MMV2408/tabchat/issues/1 (offered a rename) — 2026-10-13
- [x] v0.1.0 published: https://github.com/narendranag/tabchat/releases/tag/v0.1.0 — 2026-10-13
- [x] v0.1.0 installed in `/Applications` on mini; spike sign-in data deleted (343 MB) — 2026-10-13
- [x] Phase 6: app icon and `just dmg` → `build/Tabchat-0.1.0.dmg` (signed with Apple Development, not notarised) — 2026-10-13
- [x] Phase 5: split view, `Cmd+K`, tab sleep, duplicate/incognito, card order, link browser choice — 2026-10-13
- [x] Stable Apple Development signing for local builds — 2026-10-13
- [x] Phase 4 Mac integration (Dock/menu bar unread, notifications, pause, mute, login item, settings, menus) + Reddit and X — 2026-10-13
- [x] Phase 2 skeleton (XcodeGen, just, lint, XCTest, CI) and phase 3 core — 2026-10-13
- [x] Docs to the fleet standard (`docs/`) — 2026-10-13
- [x] Engine spike: GO (`spike/`) — 2026-10-13
- [x] Linux code to the `Linux` branch, clean `main`, README for building in public — 2026-10-13
- [x] Plan and decisions for the Mac rewrite (`brief/mac-rewrite.md`) — 2026-10-13
