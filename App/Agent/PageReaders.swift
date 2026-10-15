import Foundation
import WebKit

/// The scripts that read a page for agents. They run in their own content world, so the page's
/// scripts cannot see or change them, and they only read: no clicks, scrolls, focus or requests.
enum PageReaders {
    @MainActor static var world: WKContentWorld {
        .world(name: "tabchat-agent")
    }

    /// Chat-list readers by service id. A service without one answers "no reader".
    static func chatList(serviceId: String) -> String? {
        switch serviceId {
        case "whatsapp": whatsAppChatList
        case "discord": DiscordScripts.chats
        default: nil
        }
    }

    /// WhatsApp Web's chat list: rows in `#pane-side`; the first `span[title]` is the chat's name,
    /// the last the message preview; the unread badge's label says "unread". Ids are not read:
    /// WhatsApp's carry phone numbers.
    static let whatsAppChatList = whatsAppRows + #"""
    const pane = document.querySelector("#pane-side");
    if (!pane) return JSON.stringify({ok: false, reason: "no chat list on screen"});
    return JSON.stringify({ok: true, chats: readRows(pane)});
    """#

    /// The chat list from the top down to chats last active before `sinceMs` (local midnight of the
    /// day asked for): scrolls the list, which opens nothing, and returns to the top. Stops after three
    /// older rows in a row, so pinned chats at the top don't end it early.
    static let whatsAppChatListSince = whatsAppRows + #"""
    const pane = document.querySelector("#pane-side");
    if (!pane) return JSON.stringify({ok: false, reason: "no chat list on screen"});
    const wait = ms => new Promise(r => setTimeout(r, ms));
    const dayOf = label => {
      const now = new Date(); now.setHours(0, 0, 0, 0);
      const l = label.toLowerCase();
      const names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"];
      if (/^\d{1,2}[:.]\d{2}/.test(l) || l === "today") return now.getTime();
      if (l === "yesterday") return now.getTime() - 86400000;
      if (names.includes(l)) return now.getTime() - ((now.getDay() - names.indexOf(l) + 7) % 7) * 86400000;
      const m = l.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/);
      if (!m) return null;
      const [d, mo] = dayFirst ? [m[1], m[2]] : [m[2], m[1]];
      const y = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
      return new Date(y, Number(mo) - 1, Number(d)).getTime();
    };
    const seen = new Map();
    let older = 0;
    for (let i = 0; i < 200 && older < 3; i++) {
      for (const chat of readRows(pane)) {
        if (seen.has(chat.name)) continue;
        seen.set(chat.name, chat);
        const day = dayOf(chat.time);
        older = day !== null && day < sinceMs ? older + 1 : 0;
        if (older >= 3) break;
      }
      const before = pane.scrollTop;
      pane.scrollTop += Math.floor(pane.clientHeight * 0.8);
      await wait(300);
      if (pane.scrollTop === before) break;
    }
    pane.scrollTop = 0;
    const chats = Array.from(seen.values()).filter(c => { const d = dayOf(c.time); return d === null || d >= sinceMs; });
    return JSON.stringify({ok: true, chats});
    """#

    /// `readRows(pane)`: the chat rows WhatsApp has drawn, as `AgentChat`s.
    private static let whatsAppRows = #"""
    const readRows = pane => {
      const rows = Array.from(pane.querySelectorAll('[role="listitem"], [role="row"]'));
      const top = rows.filter(r => !rows.some(o => o !== r && o.contains(r)));
      const days = "yesterday|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday";
      const timePattern = new RegExp("^(\\d{1,2}[:.]\\d{2}(\\s?[AP]M)?|" + days + "|\\d{1,2}/\\d{1,2}/\\d{2,4})$", "i");
      return top.map(row => {
        const titled = Array.from(row.querySelectorAll("span[title]")).map(s => s.getAttribute("title") || "");
        const badge = row.querySelector('[aria-label*="unread" i]');
        let unread = 0;
        if (badge) {
          const m = ((badge.textContent || "") + " " + (badge.getAttribute("aria-label") || "")).match(/\d+/);
          unread = m ? parseInt(m[0], 10) : 1;
        }
        let time = "";
        for (const el of row.querySelectorAll("div, span")) {
          const t = el.children.length === 0 ? (el.textContent || "").trim() : "";
          if (timePattern.test(t)) { time = t; break; }
        }
        return {name: titled[0] || "", preview: titled.length > 1 ? titled[titled.length - 1] : "", time, unread};
      }).filter(c => c.name);
    };

    """#

    /// The structure under a selector: tags, roles, labels and data attributes, text only as a length
    /// unless it is short. For writing readers against a real page; debug builds only.
    static let inspect = #"""
    const root = document.querySelector(selector);
    if (!root) return "no match for " + selector;
    const lines = [];
    const walk = (el, depth) => {
      if (lines.length > 600 || depth > maxDepth) return;
      const attrs = [];
      for (const a of el.attributes) {
        if (a.name === "class" || a.name === "style") continue;
        attrs.push(a.name + "=" + JSON.stringify(a.value.slice(0, 80)));
      }
      const own = Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join("").trim();
      const text = own ? " text=" + JSON.stringify(own.slice(0, 40)) : "";
      lines.push("  ".repeat(depth) + el.tagName.toLowerCase() + (attrs.length ? " " + attrs.join(" ") : "") + text);
      for (const child of el.children) walk(child, depth + 1);
    };
    walk(root, 0);
    return lines.join("\n");
    """#

    /// Any page: its address, title and the text a person can see, capped at `max` characters.
    static let pageText = #"""
    const text = (document.body && document.body.innerText) || "";
    return JSON.stringify({url: location.href, title: document.title, text: text.slice(0, max), truncated: text.length > max});
    """#

    private struct ChatListResult: Decodable {
        var ok: Bool
        var reason: String?
        var chats: [AgentChat]?
    }

    /// Turns a chat-list reader's JSON into the API's answer; content only when `countsOnly` is off.
    static func chatsResponse(json: String, countsOnly: Bool, readOnly: Bool = false, now: Date = Date()) -> AgentResponse {
        guard let result = try? JSONDecoder().decode(ChatListResult.self, from: Data(json.utf8)) else {
            return .failure("reader returned something unreadable")
        }
        guard result.ok, var chats = result.chats else {
            return .failure(result.reason ?? "reader failed")
        }
        if readOnly {
            chats = chats.filter { $0.unread == 0 }
        }
        for index in chats.indices {
            let label = chats[index].time
            let today = label.range(of: #"^\d{1,2}[:.]\d{2}"#, options: .regularExpression) != nil
            let date = WhatsAppScripts.date(ofDay: today ? "Today" : label, now: now)
            chats[index].date = date.isEmpty ? nil : date
        }
        if countsOnly {
            return AgentResponse(ok: true, counts: counts(chats))
        }
        return AgentResponse(ok: true, untrusted: true, chats: chats)
    }

    static func counts(_ chats: [AgentChat]) -> AgentChatCounts {
        AgentChatCounts(
            chats: chats.count,
            withPreview: chats.filter { !$0.preview.isEmpty }.count,
            withTime: chats.filter { !$0.time.isEmpty }.count,
            withUnread: chats.filter { $0.unread > 0 }.count
        )
    }

    static func pageResponse(json: String) -> AgentResponse {
        guard let page = try? JSONDecoder().decode(AgentPage.self, from: Data(json.utf8)) else {
            return .failure("reader returned something unreadable")
        }
        return AgentResponse(ok: true, untrusted: true, page: page)
    }

    /// Runs a reader in the agent world of the page's main frame and returns its JSON string.
    @MainActor
    static func run(_ script: String, arguments: [String: Any] = [:], in webView: WKWebView) async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            script, arguments: arguments, in: nil, contentWorld: world
        )
        return value as? String ?? ""
    }
}
