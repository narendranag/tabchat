import Foundation

/// WhatsApp Web scripts for the agent API, written against the page's `data-testid` hooks
/// (checked live 2026-10-15). Each returns a JSON string with `ok` and, on failure, `reason`.
/// The read scripts only read. The action scripts click, and are only run for tabs whose
/// "actions" switch is on; none of them type, send or delete anything.
enum WhatsAppScripts {
    /// The open chat's visible messages. Element ids are WhatsApp's message ids, not phone numbers.
    static let messages = #"""
    const main = document.querySelector("#main");
    if (!main) return JSON.stringify({ok: false, reason: "no chat open"});
    const header = main.querySelector('[data-testid="conversation-info-header-chat-title"]');
    const chat = header ? header.textContent.trim() : "";
    const messages = Array.from(main.querySelectorAll("[data-id]")).map(el => {
      let sender = "", stamp = "";
      const pre = el.querySelector("[data-pre-plain-text]");
      if (pre) {
        const m = (pre.getAttribute("data-pre-plain-text") || "").match(/^\[([^\]]*)\]\s*(.*?):\s*$/);
        if (m) { stamp = m[1]; sender = m[2]; }
      }
      const out = !!(el.closest(".message-out") || el.querySelector(".message-out"));
      const incoming = !!(el.closest(".message-in") || el.querySelector(".message-in"));
      if (!sender) {
        const label = el.querySelector('[aria-label$=":"]');
        if (label) sender = label.getAttribute("aria-label").slice(0, -1);
      }
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
      const meta = el.querySelector('[data-testid="msg-meta"]');
      const recalled = !!el.querySelector('[data-testid="recalled"]');
      return {
        id: el.getAttribute("data-id") || "",
        direction: out ? "out" : (incoming ? "in" : ""),
        sender, stamp,
        time: meta ? meta.textContent.trim() : "",
        text: textEl ? textEl.innerText : (recalled ? "(deleted)" : ""),
        document
      };
    });
    return JSON.stringify({ok: true, chat, messages});
    """#

    /// Opens the chat named `name` from the rendered chat list and waits until its header shows.
    static let open = #"""
    const rows = Array.from(document.querySelectorAll('#pane-side [role="row"], #pane-side [role="listitem"]'));
    const row = rows.find(r => {
      const t = r.querySelector('[data-testid="cell-frame-title"] span[title], span[title]');
      return t && t.getAttribute("title") === name;
    });
    if (!row) return JSON.stringify({ok: false, reason: "that chat is not in the chat list on screen"});
    const target = row.querySelector('[data-testid="cell-frame-container"]') || row;
    for (const type of ["mousedown", "mouseup", "click"]) {
      target.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true, view: window}));
    }
    for (let i = 0; i < 50; i++) {
      const h = document.querySelector('#main [data-testid="conversation-info-header-chat-title"]');
      if (h && h.textContent.trim() === name) return JSON.stringify({ok: true, chat: name});
      await new Promise(r => setTimeout(r, 100));
    }
    return JSON.stringify({ok: false, reason: "the chat did not open"});
    """#

    /// Opens the document in message `id` and presses the viewer's Download button.
    static let download = #"""
    const msg = Array.from(document.querySelectorAll("#main [data-id]")).find(el => el.getAttribute("data-id") === id);
    if (!msg) return JSON.stringify({ok: false, reason: "that message is not on screen"});
    const thumb = msg.querySelector('[data-testid="document-thumb"]');
    if (!thumb) return JSON.stringify({ok: false, reason: "that message has no document (only documents for now)"});
    const m = (thumb.getAttribute("title") || "").match(/^View "(.*)"$/);
    thumb.click();
    for (let i = 0; i < 80; i++) {
      const button = document.querySelector('[data-testid="media-viewer-modal"] button[aria-label="Download"]');
      if (button) { button.click(); return JSON.stringify({ok: true, name: m ? m[1] : ""}); }
      await new Promise(r => setTimeout(r, 100));
    }
    return JSON.stringify({ok: false, reason: "the document viewer did not open"});
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

    /// Closes the media viewer if it is open.
    static let closeViewer = #"""
    const close = document.querySelector('[data-testid="media-viewer-modal"] [aria-label="Close"]');
    if (close) close.click();
    return JSON.stringify({ok: true});
    """#
}

extension WhatsAppScripts {
    struct Result: Decodable {
        var ok: Bool
        var reason: String?
        var chat: String?
        var name: String?
        var messages: [AgentMessage]?
        var contact: AgentContact?
    }

    static func decode(_ json: String) -> Result {
        (try? JSONDecoder().decode(Result.self, from: Data(json.utf8)))
            ?? Result(ok: false, reason: "script returned something unreadable")
    }

    static func messagesResponse(json: String) -> AgentResponse {
        let result = decode(json)
        guard result.ok, let messages = result.messages else { return .failure(result.reason ?? "reader failed") }
        var response = AgentResponse(ok: true, untrusted: true, messages: messages)
        response.chat = result.chat
        return response
    }
}
