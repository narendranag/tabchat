# Tabchat (Mac)

WhatsApp, Discord, Teams, Outlook, OneDrive, Brightspace and any website as tabs in one window,
sharing one browser engine. For Narendra, on his Macs.

A fork of [MMV2408/tabchat](https://github.com/MMV2408/tabchat) (MIT, Electron, built for Linux).
Repo: github.com/narendranag/tabchat (public fork). Remotes: `origin` = the fork, `upstream` = MMV2408.
Keep the MIT licence and the credit to the original author.

This brain follows the fleet's standard: how projects are built is in
`~/claude-computer/docs/DEV-GUIDELINES.md`, the tools on the PATH in
`~/claude-computer/claude-global/CLAUDE.md`.

**Resuming:** read `TASKS.md`, then `brief/mac-refactor.md` (the job this brain was started for).

## Status

Freshly forked (upstream v1.23.0, Electron 44). Runs on Linux only: D-Bus (`dbus-next`), the
GNOME Do-not-disturb hook, xdg autostart, `.deb`/AppImage/snap/flatpak packaging. Nothing Mac-specific
yet.

## Stack

- Electron 44, plain JavaScript, no bundler. `src/main/` (main process), `src/preload/`,
  `src/renderer/` (HTML pages). Packaging with `electron-builder` (`package.json` → `build`).
- **Deviation from DEV-GUIDELINES** (desktop = Tauri v2): it stays on Electron for now because it is
  a fork of an Electron app; whether to move is the first decision in `TASKS.md`.

## Run

```sh
npm install
npm start          # electron .
```

Build and release are Linux-only today (`npm run dist`, `.github/workflows/snap.yml`); a Mac build
is part of the refactor.
