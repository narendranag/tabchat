# Tasks — Tabchat (Mac)

<!-- Format (shared by every brain): one `- [ ]` per task; optional `📅 YYYY-MM-DD` due date and `#tags`.
     Now / Next / Later / Done. Current status is in CLAUDE.md ("Status"); decisions in DECISIONS.md. -->

## Now

- [ ] Install v0.1.0 on air (air was unreachable 2026-10-13; mini done) #mac
- [ ] **Publish the v0.1.0 release** (Narendra runs it; publishing is his step): `git tag -a v0.1.0 -m "Tabchat for Mac 0.1.0" && git push origin v0.1.0 && gh release create v0.1.0 build/Tabchat-0.1.0.dmg -R narendranag/tabchat --title "Tabchat for Mac 0.1.0" --notes-file brief/release-0.1.0.md` #release

## Next

- [ ] Delete the `.verify` leftovers from phase 2's test launch (`~/Library/*/com.narendranag.tabchat.verify*`, 129 MB) — Narendra decides #mac

## Later

- [ ] Signed, notarized `.dmg` from GitHub Actions + Sparkle updates (needs an Apple Developer ID — costs money, Narendra decides)

## Done

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
