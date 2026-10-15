import Foundation

/// Discord's web client, read only (its terms forbid automating a user account: no actions here).
/// Written against attributes Discord keeps stable while its class names change: the direct-message
/// links' `href` and `aria-label`, and the message list's `id`s and `time[datetime]` (checked live
/// 2026-10-15).
enum DiscordScripts {
    /// The direct and group messages in the sidebar: name, unread, and the channel id as a stable key.
    static let chats = #"""
    const nav = document.querySelector('nav[aria-label*="Private" i]');
    if (!nav) return JSON.stringify({ok: false, reason: "no direct messages list on screen (open Discord's home)"});
    const chats = Array.from(nav.querySelectorAll('a[href^="/channels/@me/"]')).map(a => {
      const label = a.getAttribute("aria-label") || "";
      const m = label.match(/^(?:unread,\s*)?(.*?)\s*\((direct|group) message\)/i);
      const row = a.closest("li") || a;
      const badge = row.querySelector('[class*="numberBadge"], [class*="NumberBadge"]');
      const count = badge ? parseInt(badge.textContent || "", 10) : NaN;
      const unread = !isNaN(count) ? count : (/^unread,/i.test(label) ? 1 : 0);
      return {
        name: m ? m[1] : label, preview: "", time: "", unread,
        key: (a.getAttribute("href") || "").split("/").pop(), group: !!m && m[2].toLowerCase() === "group"
      };
    }).filter(c => c.name);
    return JSON.stringify({ok: true, chats});
    """#

    /// The open conversation's drawn messages, oldest first: id, author (carried over to the follow-on
    /// messages that don't repeat it), ISO time, text without the quoted reply, attachments.
    static let messages = #"""
    const list = document.querySelector('ol[data-list-id="chat-messages"]');
    if (!list) return JSON.stringify({ok: false, reason: "no conversation open"});
    const title = document.title.replace(/^\(\d+\)\s*/, "").replace(/^Discord\s*\|\s*/, "");
    const own = (li, selector) => Array.from(li.querySelectorAll(selector))
      .filter(e => !e.closest('[id^="message-reply-context-"]'));
    let sender = "";
    const messages = Array.from(list.querySelectorAll('li[id^="chat-messages-"]')).map(li => {
      const id = li.id.split("-").pop();
      const name = own(li, '[id^="message-username-"] [data-text]')[0];
      if (name) sender = name.getAttribute("data-text") || name.textContent.trim();
      // "Joined the server" and similar notices: no author header, Discord's desaturated icon instead.
      const system = !li.querySelector("h3") && !!li.querySelector("[data-accessibility]");
      const time = own(li, "time[datetime]")[0];
      const content = own(li, '[id^="message-content-"]')[0];
      const accessories = li.querySelector('[id^="message-accessories-"]');
      const files = accessories
        ? Array.from(accessories.querySelectorAll('a[href*="/attachments/"]:not([data-role="img"])')) : [];
      const file = files.map(a => decodeURIComponent((a.getAttribute("href") || "").split("?")[0].split("/").pop() || ""))[0];
      const image = accessories && accessories.querySelector('a[data-role="img"], img[alt]:not([aria-hidden="true"])');
      const video = accessories && accessories.querySelector("video");
      return {
        id, rendered: true, direction: "", sender: system ? "" : sender,
        stamp: time ? time.getAttribute("datetime") : "", time: time ? (time.textContent || "").replace(/^—\s*/, "").trim() : "",
        text: content ? content.innerText.trim() : "",
        document: file ? {name: file, type: (file.split(".").pop() || "").toUpperCase(), details: ""} : null,
        media: video ? "video" : (image ? "image" : null)
      };
    });
    return JSON.stringify({ok: true, chat: title, messages});
    """#

    /// Discord stamps are ISO times; `date` is their local day, written like WhatsApp's.
    static func messagesResponse(json: String, calendar: Calendar = .current, locale: Locale = .current) -> AgentResponse {
        let result = WhatsAppScripts.decode(json)
        guard result.ok, var messages = result.messages else { return .failure(result.reason ?? "reader failed") }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: locale) ?? "dd/MM/yyyy"
        for index in messages.indices {
            messages[index].date = AgentResponder.isoDate(messages[index].stamp).map { formatter.string(from: $0) }
        }
        var response = AgentResponse(ok: true, untrusted: true, messages: messages)
        response.chat = result.chat
        return response
    }
}
