# Tasks — Tabchat (Mac)

<!-- Format (shared by every brain): one `- [ ]` per task; optional `📅 YYYY-MM-DD` due date and `#tags`.
     Now / Next / Later / Done. Current status is in CLAUDE.md ("Status"); decisions in DECISIONS.md. -->

## Now

- [ ] **Audit for Mac**: run it on this Mac (`npm install && npm start`), list everything Linux-only and what breaks — see `brief/mac-refactor.md` #mac
- [ ] **Decide: stay on Electron or move** (DEV-GUIDELINES says Tauri v2 for desktop). Propose with the audit; default: stay on Electron and refactor in place. Narendra decides; record in `DECISIONS.md` #mac
- [ ] **Refactor for macOS**: platform layer for tray/menu bar, dock badge, notifications, Do not disturb (Focus), login item, keyboard shortcuts (Cmd), app menu, window behaviour #mac
- [ ] **Mac build**: `electron-builder --mac` → `.dmg` (arm64 + x64), running locally; signing/notarizing later #mac

## Next

- [ ] Decide what happens to the Linux targets, the snap workflow and the auto-updater feed (they point at MMV2408's releases) #mac
- [ ] Docs to the fleet standard (`docs-build --init`) without clobbering upstream's `docs/index.html` site #docs
- [ ] README for the fork: what's different, credit to upstream

## Later

- [ ] Signed, notarized `.dmg` from GitHub Actions (needs an Apple Developer ID — costs money, Narendra decides)

## Done
