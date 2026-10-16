import Foundation

/// LinkedIn Messaging, read only: the conversation list, the open thread's messages, opening a thread
/// and scrolling it back. Nothing here types, likes, connects or sends. Written against LinkedIn's
/// long-lived `msg-*` class hooks. Each script returns JSON with `ok` and, on failure, `reason` and
/// `code` ("checkpoint" or "signed-out" when LinkedIn shows those pages instead of Messaging).
///
/// Days are ISO dates ("2026-10-14", local), worked out from LinkedIn's labels ("3:04 PM" is today,
/// "Mon", "Oct 14", "Oct 14, 2025") against `nowMs`.
enum LinkedInScripts {
    /// One row per conversation drawn in the list: name, preview, time label, unread, thread id (`key`)
    /// and profile where the row links them, `group`, and `date`.
    static let chats = prelude + #"""
    const rows = listRows();
    if (!rows) return noList();
    return JSON.stringify({ok: true, chats: rows.map(plain)});
    """#

    /// The list from the top down to conversations last active before `sinceDay` ("YYYY-MM-DD"):
    /// scrolls the list (LinkedIn loads more as it goes), opens nothing, and returns to the top.
    static let chatsSince = prelude + #"""
    const first = listRows();
    if (!first) return noList();
    const pane = scroller(document.querySelector(listSelector));
    const seen = new Map();
    let older = 0;
    for (let i = 0; i < 100 && older < 3; i++) {
      for (const row of listRows()) {
        const id = row.key || row.name;
        if (seen.has(id)) continue;
        seen.set(id, plain(row));
        older = row.date && row.date < sinceDay ? older + 1 : 0;
        if (older >= 3) break;
      }
      if (!pane || older >= 3) break;
      const height = pane.scrollHeight, before = pane.scrollTop;
      pane.scrollTop += Math.floor(pane.clientHeight * 0.8);
      await wait(400);
      for (let j = 0; j < 20 && pane.scrollTop === before && pane.scrollHeight === height; j++) await wait(100);
      if (pane.scrollTop === before && pane.scrollHeight === height) break;
    }
    if (pane) pane.scrollTop = 0;
    return JSON.stringify({ok: true, chats: Array.from(seen.values()).filter(c => !c.date || c.date >= sinceDay)});
    """#

    /// The open thread's messages, oldest first.
    static let messages = prelude + #"""
    const list = await threadList(3000);
    if (!list) return JSON.stringify({ok: false, code: "not-found", reason: "no conversation open"});
    return JSON.stringify(Object.assign({ok: true, messages: readEvents(list)}, header()));
    """#

    /// Opens the conversation named `name` (or with thread id `key`) by clicking its row, scrolling the
    /// list down to find it if needed. With `ifRead`, refuses one whose row shows unread messages.
    /// `{ok: false, code: "not-found", inList: false}` when it isn't in the list.
    static let open = prelude + #"""
    if (!listRows()) return noList();
    const want = clean(name).toLowerCase();
    const match = r => (key && r.key === key) || (!!want && r.name.toLowerCase() === want);
    const pane = scroller(document.querySelector(listSelector));
    let row = listRows().find(match);
    for (let i = 0; i < 15 && !row && pane; i++) {
      const height = pane.scrollHeight, before = pane.scrollTop;
      pane.scrollTop += Math.floor(pane.clientHeight * 0.8);
      await wait(400);
      for (let j = 0; j < 20 && pane.scrollTop === before && pane.scrollHeight === height; j++) await wait(100);
      row = listRows().find(match);
      if (pane.scrollTop === before && pane.scrollHeight === height) break;
    }
    if (!row) {
      const near = listRows().map(r => r.name).filter(n => want && n.toLowerCase().includes(want.split(" ")[0])).slice(0, 5);
      if (pane) pane.scrollTop = 0;
      return JSON.stringify({ok: false, code: "not-found", inList: false,
        reason: "no conversation " + (key ? "with that thread id" : "named " + JSON.stringify(name)) + " in the list"
          + (near.length ? "; near: " + near.join(", ") : "")});
    }
    if (ifRead && row.unread > 0) {
      if (pane) pane.scrollTop = 0;
      return JSON.stringify({ok: false, code: "refused", reason: row.name + " has unread messages; not opened"});
    }
    const target = row.row.querySelector('a[href*="/messaging/thread/"], .msg-conversation-listitem__link') || row.row;
    target.scrollIntoView({block: "nearest"});
    target.click();
    for (let i = 0; i < 100; i++) {
      const h = header();
      if ((key && h.key === key) || (want && h.chat.toLowerCase() === want)) break;
      await wait(100);
    }
    await threadList(5000);
    if (pane) pane.scrollTop = 0;
    const h = header();
    if (!((key && h.key === key) || (want && h.chat.toLowerCase() === want))) {
      return JSON.stringify({ok: false, code: "failed", reason: "clicked " + row.name + " but the thread did not open"});
    }
    return JSON.stringify(Object.assign({ok: true}, h));
    """#

    /// Whether the thread with `key` is open and drawn (after the tab was sent to its address).
    static let opened = prelude + #"""
    for (let i = 0; i < 150; i++) {
      const h = header();
      if (h.key === key && document.querySelector(threadSelector)) return JSON.stringify(Object.assign({ok: true}, h));
      await wait(100);
    }
    return JSON.stringify({ok: false, code: "not-found", reason: "the thread did not open (check the thread id)"});
    """#

    /// Scrolls the open thread up `screens` screens (LinkedIn loads earlier messages at the top), reads
    /// every message, and scrolls back to the newest. With `until`, stops once that message is loaded and
    /// returns only newer ones.
    static let history = prelude + #"""
    const list = await threadList(3000);
    if (!list) return JSON.stringify({ok: false, code: "not-found", reason: "no conversation open"});
    const pane = scroller(list);
    const deadline = Date.now() + 90000;
    const stopAt = typeof until === "string" ? until : "";
    const has = () => !!stopAt && readEvents(list).some(e => e.id === stopAt);
    let partial = false;
    for (let i = 0; pane && i < screens && !has(); i++) {
      if (Date.now() > deadline) { partial = true; break; }
      const height = pane.scrollHeight;
      pane.scrollTop = Math.max(0, pane.scrollTop - pane.clientHeight);
      await wait(500);
      for (let j = 0; j < 30 && pane.scrollTop === 0 && pane.scrollHeight === height; j++) await wait(100);
      if (pane.scrollTop === 0 && pane.scrollHeight === height) break;
    }
    let messages = readEvents(list);
    if (pane) pane.scrollTop = pane.scrollHeight;
    let reached;
    if (stopAt) {
      const at = messages.findIndex(m => m.id === stopAt);
      reached = at >= 0;
      if (reached) messages = messages.slice(at + 1);
    }
    return JSON.stringify(Object.assign({ok: true, messages, reached, partial}, header()));
    """#

    struct Result: Decodable {
        var ok: Bool
        var reason: String?
        var code: String?
        var inList: Bool?
        var chat: String?
        var key: String?
        var chatProfile: String?
        var reached: Bool?
        var partial: Bool?
        var chats: [AgentChat]?
        var messages: [AgentMessage]?
    }

    static func decode(_ json: String) -> Result {
        (try? JSONDecoder().decode(Result.self, from: Data(json.utf8)))
            ?? Result(ok: false, reason: "script returned something unreadable", code: AgentErrorCode.failed.rawValue)
    }

    static func failure(_ result: Result, _ fallback: String) -> AgentResponse {
        .failure(result.reason ?? fallback, code: result.code.flatMap(AgentErrorCode.init(rawValue:)) ?? .failed)
    }

    /// A thread id ("2-…") or a thread's address, as the id; nil for anything else (a name).
    static func threadId(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let range = trimmed.range(of: #"/messaging/thread/[^/?#]+"#, options: .regularExpression) {
            return String(trimmed[range].dropFirst("/messaging/thread/".count)).removingPercentEncoding
        }
        return trimmed.range(of: #"^2-[A-Za-z0-9+/=_-]{8,}$"#, options: .regularExpression) != nil ? trimmed : nil
    }

    static func threadURL(_ id: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        guard let escaped = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.linkedin.com/messaging/thread/\(escaped)/")
    }

    static func chatsResponse(json: String, countsOnly: Bool, readOnly: Bool) -> AgentResponse {
        let result = decode(json)
        guard result.ok, var chats = result.chats else { return failure(result, "reader failed") }
        if readOnly {
            chats = chats.filter { $0.unread == 0 }
        }
        if countsOnly {
            return AgentResponse(ok: true, counts: PageReaders.counts(chats))
        }
        return AgentResponse(ok: true, untrusted: true, chats: chats)
    }

    /// Messages with `stamp` as a full ISO time where the page gives a day and a time ("minute"), else
    /// only `date` ("day").
    static func messagesResponse(json: String, calendar: Calendar = .current) -> AgentResponse {
        let result = decode(json)
        guard result.ok, var messages = result.messages else { return failure(result, "reader failed") }
        for index in messages.indices {
            guard let date = messages[index].date else { continue }
            if let stamp = stamp(date: date, time: messages[index].time, calendar: calendar) {
                messages[index].stamp = stamp
                messages[index].precision = "minute"
            } else {
                messages[index].precision = "day"
            }
        }
        var response = AgentResponse(ok: true, untrusted: true, messages: messages)
        response.chat = result.chat
        response.key = result.key
        response.chatProfile = result.chatProfile
        return response
    }

    /// "2026-10-14" and "3:04 PM" (or "15:04") → "2026-10-14T15:04:00+05:30" in the calendar's zone.
    static func stamp(date: String, time: String, calendar: Calendar) -> String? {
        let day = date.split(separator: "-").compactMap { Int($0) }
        let pattern = #"^(\d{1,2}):(\d{2})\s?([AaPp][Mm])?$"#
        guard day.count == 3, let match = time.range(of: pattern, options: .regularExpression) else { return nil }
        let parts = time[match].split(whereSeparator: { $0 == ":" || $0 == " " })
        guard parts.count >= 2, var hour = Int(parts[0]), let minute = Int(parts[1].prefix(2)) else { return nil }
        let marker = time.lowercased()
        if marker.hasSuffix("pm"), hour < 12 {
            hour += 12
        }
        if marker.hasSuffix("am"), hour == 12 {
            hour = 0
        }
        let components = DateComponents(year: day[0], month: day[1], day: day[2], hour: hour, minute: minute)
        guard hour < 24, minute < 60, let moment = calendar.date(from: components) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: moment)
    }
}

private extension LinkedInScripts {
    /// Shared by every script: page checks, the list and thread readers, day labels.
    static let prelude = #"""
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const clean = t => (t || "").replace(/\s+/g, " ").trim();
    {
      const path = location.pathname;
      const check = /^\/(checkpoint|authwall)/.test(path)
        || !!document.querySelector('#captcha-internal, iframe[src*="captcha" i]');
      if (check) {
        return JSON.stringify({ok: false, code: "checkpoint", reason: "LinkedIn shows a security check; stop for today"});
      }
      if (/^\/(login|uas\/login|signup)/.test(path)) {
        return JSON.stringify({ok: false, code: "signed-out", reason: "LinkedIn is signed out in this tab"});
      }
    }
    const noList = () => JSON.stringify({ok: false, code: "failed",
      reason: "no LinkedIn conversation list on screen (open Messaging in the tab)"});
    const now = new Date(typeof nowMs === "number" ? nowMs : Date.now());
    const pad = n => String(n).padStart(2, "0");
    const iso = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    const months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
    const weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
    const dayOf = label => {
      const l = clean(label).toLowerCase().replace(/\./g, "");
      if (!l) return "";
      const today = new Date(now); today.setHours(0, 0, 0, 0);
      const back = n => { const d = new Date(today); d.setDate(d.getDate() - n); return iso(d); };
      if (/^\d{1,2}:\d{2}\s?(am|pm)?$/.test(l) || l === "today" || l === "now") return back(0);
      if (l === "yesterday") return back(1);
      let m = l.match(/^(\d+)\s?(d|w)$/);
      if (m) return back(Number(m[1]) * (m[2] === "w" ? 7 : 1));
      const w = weekdays.indexOf(l.slice(0, 3));
      if (w >= 0 && /^[a-z]+$/.test(l)) return back((today.getDay() - w + 7) % 7 || 7);
      m = l.match(/^([a-z]{3})[a-z]*\s+(\d{1,2})(?:,?\s+(\d{4}))?$/);
      if (m && months.includes(m[1])) {
        const mo = months.indexOf(m[1]);
        let d = new Date(m[3] ? Number(m[3]) : today.getFullYear(), mo, Number(m[2]));
        if (!m[3] && d > today) d = new Date(today.getFullYear() - 1, mo, Number(m[2]));
        return iso(d);
      }
      m = l.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
      if (m) return iso(new Date(m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]), Number(m[1]) - 1, Number(m[2])));
      return "";
    };
    const profileOf = a => {
      if (!a) return "";
      try {
        const m = new URL(a.getAttribute("href"), location.origin).pathname.match(/^\/in\/([^/]+)/);
        return m ? "https://www.linkedin.com/in/" + m[1] + "/" : "";
      } catch (e) { return ""; }
    };
    const threadOf = text => {
      const m = (text || "").match(/\/messaging\/thread\/([^/?#]+)/);
      return m ? decodeURIComponent(m[1]) : "";
    };
    const scroller = el => {
      let p = el;
      while (p && p !== document.body && !/auto|scroll/.test(getComputedStyle(p).overflowY)) p = p.parentElement;
      return p && p !== document.body ? p : null;
    };
    const listSelector = ".msg-conversations-container__conversations-list";
    const listRows = () => {
      const list = document.querySelector(listSelector);
      if (!list) return null;
      return Array.from(list.querySelectorAll("li.msg-conversation-listitem")).map(li => {
        const names = li.querySelector(
          ".msg-conversation-listitem__participant-names, .msg-conversation-card__participant-names");
        const name = clean(names && names.innerText);
        const link = li.querySelector('a[href*="/messaging/thread/"]');
        const time = clean((li.querySelector("time") || {}).innerText);
        const snippet = li.querySelector(".msg-conversation-card__message-snippet, .msg-conversation-card__message-snippet-body");
        const badge = li.querySelector(".notification-badge__count, .msg-conversation-card__unread-count");
        const count = badge ? parseInt(clean(badge.innerText), 10) : NaN;
        const marked = !!li.querySelector('[class*="--unread"]');
        const group = name.includes(",") || !!li.querySelector(
          '[class*="facepile-grid--group"], [class*="facepile-grid--3"], [class*="facepile-grid--4"]');
        return {
          row: li, name, preview: clean(snippet && snippet.innerText), time,
          unread: count > 0 ? count : (marked ? 1 : 0),
          key: threadOf(link && link.getAttribute("href")) || null,
          profile: profileOf(li.querySelector('a[href*="/in/"]')) || null,
          group, date: dayOf(time) || null
        };
      }).filter(c => c.name);
    };
    const plain = r => { const c = Object.assign({}, r); delete c.row; return c; };
    const threadSelector = ".msg-s-message-list-content";
    const threadList = async ms => {
      for (let i = 0; i < ms / 100 && !document.querySelector(threadSelector); i++) await wait(100);
      return document.querySelector(threadSelector);
    };
    const header = () => {
      const box = document.querySelector(
        ".msg-title-bar, .msg-thread__topcard, .msg-overlay-conversation-bubble-header") || document;
      // One selector at a time: a list would return the profile link (name and headline) first.
      const title = box.querySelector(".msg-entity-lockup__entity-title") || box.querySelector("h2")
        || box.querySelector(".msg-thread__link-to-profile");
      return {
        chat: clean(title && title.innerText),
        chatProfile: profileOf(box.querySelector('a[href*="/in/"]')) || null,
        key: threadOf(location.pathname) || null
      };
    };
    const readEvents = list => {
      const marksOther = !!list.querySelector(".msg-s-event-listitem--other");
      let sender = "", profile = "", time = "", dayLabel = "", date = "";
      return Array.from(list.querySelectorAll("li.msg-s-message-list__event")).flatMap(li => {
        const heading = li.querySelector(".msg-s-message-list__time-heading");
        if (heading) { dayLabel = clean(heading.innerText); date = dayOf(dayLabel); }
        const meta = li.querySelector(".msg-s-message-group__meta");
        if (meta) {
          sender = clean((meta.querySelector(".msg-s-message-group__name") || {}).innerText);
          profile = profileOf(meta.querySelector('a[href*="/in/"]') || li.querySelector('a.msg-s-message-group__profile-link'));
          time = clean((meta.querySelector(".msg-s-message-group__timestamp, time") || {}).innerText);
        }
        return Array.from(li.querySelectorAll(".msg-s-event-listitem")).map(ev => {
          const other = ev.classList.contains("msg-s-event-listitem--other");
          const body = ev.querySelector(".msg-s-event-listitem__body");
          const file = ev.querySelector(".ui-attachment__filename");
          const name = clean(file && file.innerText);
          const image = ev.querySelector(".msg-s-event-listitem__image, img.msg-s-event-listitem__image");
          return {
            id: ev.getAttribute("data-event-urn") || "", rendered: true,
            direction: marksOther ? (other ? "in" : "out") : "",
            sender, profile: profile || null, stamp: "", time, day: dayLabel || null, date: date || null,
            text: body ? body.innerText.trim() : "",
            document: name ? {name, type: (name.includes(".") ? name.split(".").pop() : "").toUpperCase(), details: ""} : null,
            media: ev.querySelector("video") ? "video" : (image ? "image" : null)
          };
        });
      });
    };

    """#
}
