import Foundation

/// WhatsApp Web scripts for the agent API, written against the page's `data-testid` hooks
/// (checked live 2026-10-15). Each returns a JSON string with `ok` and, on failure, `reason`.
/// The read scripts only read. The action scripts click, and are only run for tabs whose
/// "actions" switch is on; none of them type, send or delete anything.
enum WhatsAppScripts {
    /// The open chat's visible messages. Element ids are WhatsApp's message ids, not phone numbers.
    static let messages = prelude + reader + #"""
    return JSON.stringify({ok: true, chat, messages: Array.from(main.querySelectorAll("[data-id]")).map(readMessage)});
    """#

    /// Scrolls the open chat up `screens` screens (WhatsApp loads earlier messages as you go), then back
    /// down, reading each message once it is drawn. Scrolling is all it does: nothing is clicked.
    static let history = prelude + reader + #"""
    // A chat just opened may take a moment to draw; after a restart it may show only WhatsApp's
    // "get older messages from your phone", with no message yet. Wait, then press that once.
    const pause = ms => new Promise(r => setTimeout(r, ms));
    for (let i = 0; i < 30 && !main.querySelector("[data-id]"); i++) await pause(100);
    if (!main.querySelector("[data-id]")) {
      const button = Array.from(main.querySelectorAll("button")).find(b => /older messages/i.test(b.innerText || ""));
      if (button) {
        button.click();
        for (let i = 0; i < 50 && !main.querySelector("[data-id]"); i++) await pause(100);
      }
    }
    const first = main.querySelector("[data-id]");
    if (!first) return JSON.stringify({ok: true, chat, messages: []});
    // The message list's scroll area: the nearest ancestor that scrolls, even if a short chat
    // does not overflow it yet.
    let pane = first.parentElement;
    while (pane && pane !== document.body && !/auto|scroll/.test(getComputedStyle(pane).overflowY)) {
      pane = pane.parentElement;
    }
    if (!pane || pane === document.body) {
      return JSON.stringify({ok: false, reason: "could not find the message list's scroll area"});
    }
    const wait = ms => new Promise(r => setTimeout(r, ms));
    // With `until`, stop as soon as that message is in the list: everything newer is below it.
    const stopAt = typeof until === "string" ? until : "";
    const reachedStop = () => !!stopAt && !!main.querySelector('[data-id="' + CSS.escape(stopAt) + '"]');
    for (let i = 0; i < screens && !reachedStop(); i++) {
      const height = pane.scrollHeight;
      pane.scrollTop = Math.max(0, pane.scrollTop - pane.clientHeight);
      await wait(500);
      // At the top: give WhatsApp up to two seconds to load more. After a restart it keeps only the
      // newest messages and offers "Click here to get older messages from your phone"; press that once
      // a screen and wait up to five more seconds. Nothing loading means the start of the chat.
      for (let j = 0; j < 20 && pane.scrollTop === 0 && pane.scrollHeight === height; j++) await wait(100);
      const older = Array.from(main.querySelectorAll("button")).find(b => /older messages/i.test(b.innerText || ""));
      if (pane.scrollTop === 0 && pane.scrollHeight === height && older) {
        older.click();
        for (let j = 0; j < 50 && pane.scrollHeight === height; j++) await wait(100);
      }
      if (pane.scrollTop === 0 && pane.scrollHeight === height) break;
    }
    // Each new message goes right after the known message drawn before it, so a row WhatsApp keeps
    // drawn while scrolling (the newest, say) does not land out of order.
    const seen = new Map();
    const order = [];
    const collect = () => {
      let at = -1;
      for (const el of main.querySelectorAll("[data-id]")) {
        const id = el.getAttribute("data-id") || "";
        if (seen.has(id)) { at = order.indexOf(id); continue; }
        const message = readMessage(el);
        if (!message.rendered) continue;
        seen.set(id, message);
        order.splice(at + 1, 0, id);
        at += 1;
      }
    };
    // WhatsApp adds rows back at the bottom a moment after they scroll into reach, so at the bottom
    // wait up to two seconds for more before stopping.
    for (let i = 0, idle = 0; i < 400 && idle < 8; i++) {
      collect();
      const before = pane.scrollTop;
      pane.scrollTop += Math.floor(pane.clientHeight * 0.7);
      idle = pane.scrollTop === before ? idle + 1 : 0;
      await wait(250);
    }
    collect();
    pane.scrollTop = pane.scrollHeight;
    let ids = order;
    const reached = !stopAt || order.includes(stopAt);
    if (stopAt && reached) ids = order.slice(order.indexOf(stopAt) + 1);
    return JSON.stringify({ok: true, chat, reached, messages: ids.map(id => seen.get(id))});
    """#

    /// Finds the open chat: `main` and its title `chat`.
    private static let prelude = #"""
    const main = document.querySelector("#main");
    if (!main) return JSON.stringify({ok: false, reason: "no chat open"});
    const header = main.querySelector('[data-testid="conversation-info-header-chat-title"]');
    // WhatsApp draws emoji as <img alt="🐒">; read them back so names match the chat list's titles.
    const label = el => {
      const copy = el.cloneNode(true);
      copy.querySelectorAll("img[alt]").forEach(img => img.replaceWith(img.getAttribute("alt")));
      return copy.textContent.trim();
    };
    const chat = header ? label(header) : "";

    """#

    /// `readMessage(el)`: one `[data-id]` element as an `AgentMessage`.
    private static let reader = #"""
    // The day divider above a message ("Today", "Friday", "14/10/2026"), a sibling of the message's row
    // in the list. Dividers stay drawn when the messages around them are scrolled out of view.
    const dayPattern = new RegExp("^(today|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|"
      + "\\d{1,4}[/.-]\\d{1,2}[/.-]\\d{1,4})$", "i");
    const dayOf = el => {
      // WhatsApp wraps each row in divs of the list; look among the row's siblings, then each wrapper's.
      let level = el.closest('[role="row"]') || el;
      for (let depth = 0; level && depth < 4 && level !== main; depth++, level = level.parentElement) {
        for (let node = level.previousElementSibling; node; node = node.previousElementSibling) {
          if (node.matches("[data-id]") || node.querySelector("[data-id]")) continue;
          const text = (node.innerText || node.textContent || "").trim();
          if (dayPattern.test(text)) return text;
        }
      }
      return "";
    };
    const readMessage = el => {
      const id = el.getAttribute("data-id") || "";
      const day = dayOf(el) || null;
      if (el.querySelector('[data-virtualized="true"]')) {
        return {id, day, direction: "", sender: "", stamp: "", time: "", text: "", document: null, rendered: false};
      }
      let sender = "", stamp = "";
      const pre = el.querySelector("[data-pre-plain-text]");
      if (pre) {
        const m = (pre.getAttribute("data-pre-plain-text") || "").match(/^\[([^\]]*)\]\s*(.*?):\s*$/);
        if (m) { stamp = m[1]; sender = m[2]; }
      }
      // Outgoing bubbles carry a status tick (sent, delivered, read) in their meta; incoming ones do not.
      const ticks = Array.from(el.querySelectorAll('[data-testid="msg-meta"] svg title, [data-testid="msg-meta"] [data-icon]'))
        .map(t => t.textContent + " " + (t.getAttribute("data-icon") || "")).join(" ");
      const out = /check|read|deliver|clock|pending|sent/i.test(ticks) || !!el.querySelector(".message-out");
      const incoming = !out;
      if (!sender) {
        const label = el.querySelector('[aria-label$=":"]');
        if (label) sender = label.getAttribute("aria-label").slice(0, -1);
      }
      // A one-to-one chat's incoming messages are the contact's.
      const group = !!main.querySelector('[data-testid="conversation-info-header"] [title*=","]');
      if (!sender && incoming && !group) sender = chat;
      const textEl = el.querySelector('[data-testid="selectable-text"]')
        || el.querySelector('[data-testid="document-caption selectable-text"]');
      let document = null;
      const thumb = el.querySelector('[data-testid="document-thumb"]');
      if (thumb) {
        const m = (thumb.getAttribute("title") || "").match(/^View "(.*)"$/);
        const type = thumb.querySelector('[data-testid="type"]');
        const details = Array.from(thumb.querySelectorAll("span[title]")).map(s => s.getAttribute("title"));
        document = {name: m ? m[1] : "", type: type ? type.getAttribute("title") : "", details: details.join(" • ")};
      }
      const mediaEl = thumb ? null
        : el.querySelector('[data-testid="image-thumb"], [data-testid="video-content"], img[src^="blob:"]');
      const media = mediaEl ? (mediaEl.matches('[data-testid="video-content"]') ? "video" : "image") : null;
      const meta = el.querySelector('[data-testid="msg-meta"]');
      const recalled = !!el.querySelector('[data-testid="recalled"]');
      return {
        id, day,
        rendered: true,
        direction: out ? "out" : (incoming ? "in" : ""),
        sender, stamp,
        time: meta ? ((meta.textContent.match(/\d{1,2}[:.]\d{2}(\s?[ap]\.?m\.?)?/i) || [""])[0]) : "",
        text: textEl ? textEl.innerText : (recalled ? "(deleted)" : ""),
        document, media
      };
    };

    """#

    /// Opens the chat named `name` and waits until its header shows. A chat that is not in the chat
    /// list on screen is looked up with WhatsApp's search box (in `#side`, never the message box), and
    /// the search is cleared again afterwards. Only an exact name match is opened.
    static let open = #"""
    // WhatsApp draws emoji as <img alt="🐒">; read them back so names match the chat list's titles.
    const label = el => {
      const copy = el.cloneNode(true);
      copy.querySelectorAll("img[alt]").forEach(img => img.replaceWith(img.getAttribute("alt")));
      return copy.textContent.trim();
    };
    const wait = ms => new Promise(r => setTimeout(r, ms));
    // A row's name; your own chat may also be asked for as "<name> (You)". Address-book contacts
    // who are not on WhatsApp (an "Invite" row) are never matched.
    const findRow = () => Array.from(document.querySelectorAll('#pane-side [role="row"], #pane-side [role="listitem"]'))
      .find(r => {
        const t = r.querySelector('[data-testid="cell-frame-title"] span[title]');
        if (!t || r.querySelector('[data-testid="out-contact-cell"]')) return false;
        const title = t.getAttribute("title");
        return title === name || (!!r.querySelector('[data-testid="you-label"]') && title + " (You)" === name);
      });
    const searchBox = () => document.querySelector('#side [data-testid="chat-list-search-container"] input[type="text"]');
    // Just after a restart WhatsApp is still loading: wait up to ten seconds for the list or the search box.
    for (let i = 0; i < 100 && !findRow() && !searchBox(); i++) await wait(100);
    const search = searchBox();
    const type = text => {
      search.focus();
      search.select();
      if (!(document.activeElement === search && document.execCommand("insertText", false, text))) {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(search, text);
        search.dispatchEvent(new Event("input", {bubbles: true}));
      }
    };
    let row = findRow(), searched = false;
    if (!row && search && !search.closest("#main, footer")) {
      searched = true;
      type(name.replace(/ \(You\)$/, ""));
      for (let i = 0; i < 50 && !row; i++) { await wait(100); row = findRow(); }
    }
    const clear = async () => {
      if (!searched) return;
      type("");
      await wait(200);
      search.blur();
    };
    if (!row) {
      // Name the near misses (at most five), so the caller can retry with the exact name.
      const found = searched ? Array.from(document.querySelectorAll('#pane-side [data-testid="cell-frame-title"] span[title]'))
        .map(t => t.getAttribute("title")).filter((t, i, all) => t && all.indexOf(t) === i).slice(0, 5) : [];
      await clear();
      const reason = !searched ? "that chat is not on screen and WhatsApp's search box is not there (still loading?)"
        : "no chat with that exact name" + (found.length ? "; search found: " + found.join(" | ") : "");
      return JSON.stringify({ok: false, reason});
    }
    // With ifRead, a row showing unread messages is left alone: opening it would mark them read.
    if (typeof ifRead !== "undefined" && ifRead === true && row.querySelector('[aria-label*="unread" i]')) {
      await clear();
      return JSON.stringify({ok: false, reason: "that chat has unread messages; not opened"});
    }
    const target = row.querySelector('[data-testid="cell-frame-container"], [data-testid="message-yourself-row"]') || row;
    for (const kind of ["mousedown", "mouseup", "click"]) {
      target.dispatchEvent(new MouseEvent(kind, {bubbles: true, cancelable: true, view: window}));
    }
    // Opened when the header shows the name, or, for chats whose header differs from their list title
    // (your own chat may be asked for as "<name> (You)"), when WhatsApp marks the clicked row selected.
    const selected = () => !!row.querySelector('[aria-selected="true"]') || row.getAttribute("aria-selected") === "true";
    for (let i = 0; i < 50; i++) {
      const h = document.querySelector('#main [data-testid="conversation-info-header-chat-title"]');
      if (h && (label(h) === name || label(h) === name.replace(/ \(You\)$/, "") || selected())) {
        const chat = label(h);
        await clear();
        return JSON.stringify({ok: true, chat});
      }
      await wait(100);
    }
    await clear();
    return JSON.stringify({ok: false, reason: "the chat did not open"});
    """#

    /// The open chat's contact info: opens the panel from the chat header if needed, reads the name,
    /// the phone number and the "About" line, and closes the panel again if it opened it.
    static let contact = #"""
    const header = document.querySelector('#main [data-testid="conversation-info-header"]');
    if (!header) return JSON.stringify({ok: false, reason: "no chat open"});
    let drawer = document.querySelector('[data-testid="chat-info-drawer"]');
    const opened = !drawer;
    if (opened) {
      header.click();
      for (let i = 0; i < 50 && !drawer; i++) {
        await new Promise(r => setTimeout(r, 100));
        drawer = document.querySelector('[data-testid="chat-info-drawer"]');
      }
      if (!drawer) return JSON.stringify({ok: false, reason: "contact info did not open"});
      await new Promise(r => setTimeout(r, 300));
    }
    const nameEl = drawer.querySelector('[data-testid="contact-info-subtitle selectable-text"]');
    const phonePattern = /^\+?[\d\s()-]{7,}$/;
    const texts = Array.from(drawer.querySelectorAll('[data-testid="selectable-text"]')).map(e => e.innerText.trim());
    const phone = texts.find(t => phonePattern.test(t)) || "";
    let about = "";
    const leaves = Array.from(drawer.querySelectorAll("span, div")).filter(e => e.children.length === 0);
    const label = leaves.find(e => e.textContent.trim() === "About");
    if (label) {
      const box = label.parentElement && label.parentElement.parentElement;
      const value = box ? Array.from(box.querySelectorAll('[data-testid="selectable-text"], span[dir="auto"]'))
        .map(e => e.innerText.trim()).find(t => t && t !== "About") : "";
      about = value || "";
    }
    const name = nameEl ? nameEl.innerText.trim() : "";
    if (opened) {
      const close = drawer.querySelector('button[aria-label="Close"]');
      if (close) close.click();
    }
    return JSON.stringify({ok: !!(name || phone), reason: name || phone ? null : "no contact details found",
      contact: {name, phone, about}});
    """#

    /// Closes the media viewer if it is open, and waits until it has gone.
    static let closeViewer = #"""
    for (let i = 0; i < 30; i++) {
      const close = document.querySelector('[data-testid="media-viewer-modal"] [aria-label="Close"]');
      if (!close) return JSON.stringify({ok: true});
      close.click();
      await new Promise(r => setTimeout(r, 100));
    }
    return JSON.stringify({ok: false, reason: "the viewer did not close"});
    """#
}

extension WhatsAppScripts {
    struct Result: Decodable {
        var ok: Bool
        var reason: String?
        var chat: String?
        var name: String?
        var kind: String?
        var reached: Bool?
        var count: Int?
        var total: Int?
        var messages: [AgentMessage]?
        var contact: AgentContact?
    }

    static func decode(_ json: String) -> Result {
        (try? JSONDecoder().decode(Result.self, from: Data(json.utf8)))
            ?? Result(ok: false, reason: "script returned something unreadable")
    }

    /// The date part of a stamp ("1:03 pm, 14/10/2026" → "14/10/2026").
    static func date(of stamp: String) -> String {
        guard let comma = stamp.lastIndex(of: ",") else { return "" }
        return stamp[stamp.index(after: comma)...].trimmingCharacters(in: .whitespaces)
    }

    /// The date a day divider stands for, written like WhatsApp's stamps ("14/10/2026" in most
    /// locales): dates as they are, "Today", "Yesterday" and weekday names (the last week) counted
    /// back from `now`. "" for anything else.
    static func date(ofDay day: String, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let label = day.trimmingCharacters(in: .whitespaces)
        if label.range(of: #"^\d{1,4}[/.-]\d{1,2}[/.-]\d{1,4}$"#, options: .regularExpression) != nil {
            return label
        }
        let english = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let back: Int
        switch label.lowercased() {
        case "today": back = 0
        case "yesterday": back = 1
        default:
            guard let weekday = english.firstIndex(of: label.lowercased()) else { return "" }
            let todayIndex = calendar.component(.weekday, from: now) - 1
            back = (todayIndex - weekday + 7) % 7
        }
        guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale) ?? "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    /// Fills `date` for every message: from its own stamp, else from the day divider above it, else from
    /// its neighbours when the dated messages before and after it share a day (messages are in order,
    /// so it must be that day). Otherwise it stays nil.
    static func datedMessages(_ messages: [AgentMessage], now: Date = Date()) -> [AgentMessage] {
        let own = messages.map { message in
            let stamped = date(of: message.stamp)
            return stamped.isEmpty ? date(ofDay: message.day ?? "", now: now) : stamped
        }
        var before = [String](repeating: "", count: own.count)
        var after = before
        var last = ""
        for index in own.indices {
            if !own[index].isEmpty {
                last = own[index]
            }
            before[index] = last
        }
        last = ""
        for index in own.indices.reversed() {
            if !own[index].isEmpty {
                last = own[index]
            }
            after[index] = last
        }
        return messages.indices.map { index in
            var message = messages[index]
            let date = own[index].isEmpty ? (before[index] == after[index] ? before[index] : "") : own[index]
            message.date = date.isEmpty ? nil : date
            return message
        }
    }

    static func messagesResponse(json: String) -> AgentResponse {
        let result = decode(json)
        guard result.ok, let messages = result.messages else { return .failure(result.reason ?? "reader failed") }
        var response = AgentResponse(ok: true, untrusted: true, messages: datedMessages(messages))
        response.chat = result.chat
        return response
    }
}
