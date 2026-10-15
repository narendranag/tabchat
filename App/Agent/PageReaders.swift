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
        serviceId == "whatsapp" ? whatsAppChatList : nil
    }

    /// WhatsApp Web's chat list: rows in `#pane-side`; the first `span[title]` is the chat's name,
    /// the last the message preview; the unread badge's label says "unread". Ids are not read:
    /// WhatsApp's carry phone numbers.
    static let whatsAppChatList = #"""
    const pane = document.querySelector("#pane-side");
    if (!pane) return JSON.stringify({ok: false, reason: "no chat list on screen"});
    const rows = Array.from(pane.querySelectorAll('[role="listitem"], [role="row"]'));
    const top = rows.filter(r => !rows.some(o => o !== r && o.contains(r)));
    const days = "yesterday|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday";
    const timePattern = new RegExp("^(\\d{1,2}[:.]\\d{2}(\\s?[AP]M)?|" + days + "|\\d{1,2}/\\d{1,2}/\\d{2,4})$", "i");
    const chats = top.map(row => {
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
    return JSON.stringify({ok: true, chats});
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
    static func chatsResponse(json: String, countsOnly: Bool) -> AgentResponse {
        guard let result = try? JSONDecoder().decode(ChatListResult.self, from: Data(json.utf8)) else {
            return .failure("reader returned something unreadable")
        }
        guard result.ok, let chats = result.chats else {
            return .failure(result.reason ?? "reader failed")
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
