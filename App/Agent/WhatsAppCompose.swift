import Foundation

/// `draft` and `send`: the only scripts that type into a chat.
extension WhatsAppScripts {
    /// Types `text` into the open chat's message box (`#main footer`, never the search box), line by
    /// line with line breaks, never Return. With `send`, then clicks WhatsApp's Send button and waits
    /// for the box to empty. Refuses when the open chat isn't `chat` or the box already holds text.
    static let compose = #"""
    const wait = ms => new Promise(r => setTimeout(r, ms));
    // WhatsApp draws emoji as <img alt="🐒">; read them back so names match the chat list's titles.
    const label = el => {
      const copy = el.cloneNode(true);
      copy.querySelectorAll("img[alt]").forEach(img => img.replaceWith(img.getAttribute("alt")));
      return copy.textContent.trim();
    };
    const header = document.querySelector('#main [data-testid="conversation-info-header-chat-title"]');
    if (!header) return JSON.stringify({ok: false, reason: "no chat open"});
    if (chat && label(header) !== chat) return JSON.stringify({ok: false, reason: "a different chat is open"});
    const box = document.querySelector('#main footer [contenteditable="true"]');
    if (!box || box.closest("#side")) return JSON.stringify({ok: false, reason: "no message box in the open chat"});
    if (box.innerText.trim()) return JSON.stringify({ok: false, reason: "the message box already has text; clear it first"});
    box.focus();
    if (document.activeElement !== box && !box.contains(document.activeElement)) {
      return JSON.stringify({ok: false, reason: "could not focus the message box"});
    }
    text.split(/\r?\n/).forEach((line, i) => {
      if (i) document.execCommand("insertLineBreak");
      if (line) document.execCommand("insertText", false, line);
    });
    await wait(150);
    const flat = s => s.replace(/\s+/g, " ").trim();
    if (flat(box.innerText) !== flat(text)) {
      return JSON.stringify({ok: false, reason: "the message box does not hold the text as given; check it in Tabchat"});
    }
    if (!send) return JSON.stringify({ok: true, chat: label(header)});
    const icon = document.querySelector('#main footer button[aria-label="Send"], #main footer [data-icon="wds-ic-send-filled"], '
      + '#main footer [data-icon="send"]');
    const button = icon && (icon.closest("button") || icon);
    if (!button) return JSON.stringify({ok: false, reason: "no Send button; the text is left in the message box"});
    button.click();
    for (let i = 0; i < 50; i++) {
      await wait(100);
      if (!box.innerText.trim()) return JSON.stringify({ok: true, chat: label(header)});
    }
    return JSON.stringify({ok: false, reason: "the message may not have gone; check the chat in Tabchat"});
    """#
}
