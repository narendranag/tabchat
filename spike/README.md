# Tabchat engine spike

Throwaway. Answers one question: is WKWebView good enough for every service? It is deleted after
the go/no-go, and the result goes in `DECISIONS.md`.

One WKWebView per tab, one `WKWebsiteDataStore` per profile (stable UUID from the profile name),
a fake `Notification` API that forwards to macOS notifications, unread count from the page title.
The Diagnostics item in the sidebar logs permissions, notifications, popups, downloads and errors.
Safari > Develop lets you inspect any tab.

## Build and run

```sh
cd spike && just run          # or: just -f spike/justfile run
```

Needs Xcode (macOS 14+ SDK). `build.sh` builds with SwiftPM, assembles `build/Tabchat Spike.app`
and signs it ad hoc. Allow notifications, camera and microphone when macOS asks. Cmd+1..8 switches tabs.

## Checklist

| Check | How | Result | Notes |
| --- | --- | --- | --- |
| WhatsApp 1 sign-in survives quit + relaunch | Sign in, Cmd+Q, reopen | | |
| WhatsApp 2 is a separate account | Sign in with another number | | |
| Teams sign-in, then Outlook/OneDrive already signed in | Sign in to Teams, open the other two | | |
| Personal Outlook separate from work | Sign in with a personal account | | |
| Brightspace school SSO | Enter the URL, sign in with the school account | | |
| Notification arrives, click opens the right tab | Message yourself from your phone, click the banner | | |
| Unread badge on tab and Dock | Same message; check sidebar and Dock icon | | |
| Teams call with mic + camera | Start a call | | |
| Teams screen share | Share during a call | | |
| Discord voice | Join a voice channel | | |
| Discord screen share | Go Live | | |
| File upload | Attach a file in WhatsApp | | |
| Download | Save an attachment from Outlook (lands in ~/Downloads) | | |
| Memory | Open all tabs; Activity Monitor total for "Tabchat Spike" + its WebKit processes | | |

Copy the Diagnostics log along with the table when reporting.
