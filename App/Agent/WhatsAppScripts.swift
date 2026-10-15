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
    const first = main.querySelector("[data-id]");
    if (!first) return JSON.stringify({ok: true, chat, messages: []});
    let pane = first.parentElement;
    while (pane && pane !== main) {
      const overflow = getComputedStyle(pane).overflowY;
      if ((overflow === "auto" || overflow === "scroll") && pane.scrollHeight > pane.clientHeight) break;
      pane = pane.parentElement;
    }
    if (!pane || pane === main) return JSON.stringify({ok: false, reason: "could not find the message list's scroll area"});
    const wait = ms => new Promise(r => setTimeout(r, ms));
    for (let i = 0; i < screens; i++) {
      const height = pane.scrollHeight;
      pane.scrollTop = Math.max(0, pane.scrollTop - pane.clientHeight);
      await wait(500);
      // At the top: give WhatsApp up to two seconds to load more, else this is the start of the chat.
      for (let j = 0; j < 20 && pane.scrollTop === 0 && pane.scrollHeight === height; j++) await wait(100);
      if (pane.scrollTop === 0 && pane.scrollHeight === height) break;
    }
    const seen = new Map();
    const collect = () => {
      for (const el of main.querySelectorAll("[data-id]")) {
        const message = readMessage(el);
        if (message.rendered && !seen.has(message.id)) seen.set(message.id, message);
      }
    };
    for (let i = 0; i < 400; i++) {
      collect();
      if (pane.scrollTop + pane.clientHeight >= pane.scrollHeight - 2) break;
      const before = pane.scrollTop;
      pane.scrollTop += Math.floor(pane.clientHeight * 0.7);
      if (pane.scrollTop === before) break;
      await wait(250);
    }
    collect();
    pane.scrollTop = pane.scrollHeight;
    return JSON.stringify({ok: true, chat, messages: Array.from(seen.values())});
    """#

    /// Finds the open chat: `main` and its title `chat`.
    private static let prelude = #"""
    const main = document.querySelector("#main");
    if (!main) return JSON.stringify({ok: false, reason: "no chat open"});
    const header = main.querySelector('[data-testid="conversation-info-header-chat-title"]');
    const chat = header ? header.textContent.trim() : "";

    """#

    /// `readMessage(el)`: one `[data-id]` element as an `AgentMessage`.
    private static let reader = #"""
    const readMessage = el => {
      const id = el.getAttribute("data-id") || "";
      if (el.querySelector('[data-virtualized="true"]')) {
        return {id, direction: "", sender: "", stamp: "", time: "", text: "", document: null, rendered: false};
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
        id,
        rendered: true,
        direction: out ? "out" : (incoming ? "in" : ""),
        sender, stamp,
        time: meta ? ((meta.textContent.match(/\d{1,2}[:.]\d{2}(\s?[ap]\.?m\.?)?/i) || [""])[0]) : "",
        text: textEl ? textEl.innerText : (recalled ? "(deleted)" : ""),
        document, media
      };
    };

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

    /// Opens the document, photo or video in message `id` and presses the viewer's Download button.
    /// Any viewer still open (from an earlier download) is closed first, so its button is never pressed
    /// for the wrong message.
    static let download = #"""
    const viewer = () => document.querySelector('[data-testid="media-viewer-modal"]');
    for (let i = 0; i < 30 && viewer(); i++) {
      const close = viewer().querySelector('[aria-label="Close"]');
      if (close) close.click();
      await new Promise(r => setTimeout(r, 100));
    }
    if (viewer()) return JSON.stringify({ok: false, reason: "a media viewer is still open; try again"});
    const find = () => Array.from(document.querySelectorAll("#main [data-id]")).find(el => el.getAttribute("data-id") === id);
    let msg = find();
    if (!msg) return JSON.stringify({ok: false, reason: "that message is not in the open chat"});
    // Scrolled out of view: bring it back so WhatsApp draws it.
    for (let i = 0; i < 30 && msg.querySelector('[data-virtualized="true"]'); i++) {
      msg.scrollIntoView({block: "center"});
      await new Promise(r => setTimeout(r, 100));
      msg = find() || msg;
    }
    const thumb = msg.querySelector('[data-testid="document-thumb"]');
    let target = thumb, name = "", kind = "document";
    if (thumb) {
      const m = (thumb.getAttribute("title") || "").match(/^View "(.*)"$/);
      name = m ? m[1] : "";
    } else {
      const media = msg.querySelector('[data-testid="image-thumb"], [data-testid="video-content"], img[src^="blob:"]');
      if (media) {
        target = media.closest('[role="button"]') || media;
        kind = media.matches('[data-testid="video-content"]') ? "video" : "image";
      }
    }
    if (!target) return JSON.stringify({ok: false, reason: "that message has no document, photo or video"});
    target.click();
    for (let i = 0; i < 80; i++) {
      const button = viewer() && viewer().querySelector('button[aria-label="Download"]');
      if (button) { button.click(); return JSON.stringify({ok: true, name, kind}); }
      await new Promise(r => setTimeout(r, 100));
    }
    return JSON.stringify({ok: false, reason: "the viewer did not open"});
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
