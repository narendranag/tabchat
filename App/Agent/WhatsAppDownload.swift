import Foundation

/// `download`: open a document, photo or video in WhatsApp's viewer and press its Download.
extension WhatsAppScripts {
    /// Opens the document, photo or video in message `id` and presses the viewer's Download button. For
    /// an album, `index` picks the photo; `count` is how many it shows, `total` how many it says it holds.
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
    // Bring it into view so WhatsApp draws it (an album's marker sits above its data-id, so always scroll).
    msg.scrollIntoView({block: "center"});
    await new Promise(r => setTimeout(r, 300));
    msg = find() || msg;
    for (let i = 0; i < 30 && msg.querySelector('[data-virtualized="true"]'); i++) {
      msg.scrollIntoView({block: "center"});
      await new Promise(r => setTimeout(r, 100));
      msg = find() || msg;
    }
    const thumb = msg.querySelector('[data-testid="document-thumb"]');
    let target = thumb, name = "", kind = "document", count = 1, total = 1;
    if (thumb) {
      const m = (thumb.getAttribute("title") || "").match(/^View "(.*)"$/);
      name = m ? m[1] : "";
    } else {
      const media = Array.from(msg.querySelectorAll('[data-testid="image-thumb"], [data-testid="video-content"]'));
      if (!media.length && msg.querySelector('img[src^="blob:"]')) media.push(msg.querySelector('img[src^="blob:"]'));
      count = media.length;
      // An album says how many it holds ("Media album 6 photos") and may show only the first few.
      const album = msg.matches('[data-testid="image-album"]') ? msg : msg.querySelector('[data-testid="image-album"]');
      const held = ((album && album.getAttribute("aria-label")) || "").match(/(\d+)\s+(photos|videos|items)/i);
      total = held ? Number(held[1]) : count;
      const pick = typeof index === "number" ? index : 0;
      if (count && pick >= count) return JSON.stringify({ok: false, reason: "that message has no item " + pick});
      const media1 = media[pick];
      if (media1) {
        target = media1.closest('[role="button"]') || media1;
        kind = media1.matches('[data-testid="video-content"]') ? "video" : "image";
      }
    }
    if (!target) return JSON.stringify({ok: false, reason: "that message has no document, photo or video"});
    for (const type of ["mousedown", "mouseup", "click"]) {
      target.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true, view: window}));
    }
    // The viewer has Download on its toolbar, except for your own media, where it is in the viewer's
    // Menu. Only an item named exactly "Download" is ever pressed.
    const done = () => JSON.stringify({ok: true, name, kind, count, total});
    for (let i = 0; i < 80; i++) {
      const open = viewer();
      const button = open && open.querySelector('button[aria-label="Download"]');
      if (button) { button.click(); return done(); }
      const menu = open && open.querySelector('button[aria-label="Menu"]');
      if (menu && i >= 10) {
        // The menu opens on a pointer press, not on a bare click.
        for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
          const Event = type.startsWith("pointer") ? PointerEvent : MouseEvent;
          menu.dispatchEvent(new Event(type, {bubbles: true, cancelable: true, view: window}));
        }
        for (let j = 0; j < 30; j++) {
          await new Promise(r => setTimeout(r, 100));
          const item = Array.from(document.querySelectorAll('[role="menuitem"], [role="application"] li, li[role="button"]'))
            .find(el => el.getAttribute("aria-label") === "Download" || (el.innerText || "").trim() === "Download");
          if (item) { item.click(); return done(); }
        }
        return JSON.stringify({ok: false, reason: "the viewer has no Download"});
      }
      await new Promise(r => setTimeout(r, 100));
    }
    return JSON.stringify({ok: false, reason: "the viewer did not open"});
    """#
}
