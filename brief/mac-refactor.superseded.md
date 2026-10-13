# Brief — refactor Tabchat for the Mac

From the fleet session on mini, 2026-10-13. Narendra forked tabchat and wants it working as a
proper Mac app.

## The job

Make Tabchat a first-class macOS app: runs, looks and behaves like a Mac app, packaged as a `.dmg`.

## What's Linux-only today (starting points, not exhaustive)

- `src/main/tray.js` — tray icon at "top right" of a GNOME panel → Mac menu bar extra (template image).
- `src/main/dnd.js` — follows Ubuntu's Do not disturb (gsettings/D-Bus) → macOS Focus, or drop.
- `src/main/notify-helper.js`, `notify.js`, `notifier.js` — D-Bus notifications (`dbus-next`) → Electron `Notification` on Mac.
- `src/main/unread.js`, `icons.js` — dock count is a Unity launcher API → `app.dock.setBadge`.
- `src/main/autostart.js` — xdg autostart → `app.setLoginItemSettings`.
- `src/main/updater.js`, `changelog.js`, `donate.js`, `whatsnew.js` — point at MMV2408's releases and sponsor page; decide what to keep.
- Shortcuts written as `Ctrl+…` → `CommandOrControl`; no app menu (Mac needs one for Cmd-C/V/Q).
- `package.json` `build` and `.github/workflows/snap.yml` — Linux targets only.
- User agent string, window close-to-tray behaviour, `i18n.js` (English + Dutch) strings mentioning Linux/Ubuntu.

## How

- Keep a small platform layer so upstream fixes can still be merged from `upstream/main`; don't rewrite what works.
- First task is an audit plus the Electron-or-Tauri proposal (TASKS.md, Now). Narendra decides that one.
- Anything that costs money (Apple Developer ID) or publishes (releases) — ask first.
