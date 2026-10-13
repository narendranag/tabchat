import Foundation

/// One constant to change if a service rejects the user agent.
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    + "(KHTML, like Gecko) Version/18.5 Safari/605.1.15"

enum BridgeScript {
    static let handlerName = "tabchat"

    /// Injected at document start in every frame. WKWebView has no Notification API, so sites that
    /// feature-detect it would never ask; the shim reports "granted" and forwards each notification
    /// to the app. The main frame also reports its title, where chat sites put the unread count.
    static let source = #"""
    (function () {
      if (window.__tabchatBridge) return;
      window.__tabchatBridge = true;
      const post = (m) => { try { window.webkit.messageHandlers.tabchat.postMessage(m); } catch (e) {} };
      const notify = (title, options) => {
        options = options || {};
        post({type: "notification", title: String(title), body: String(options.body || ""),
              tag: String(options.tag || ""), icon: String(options.icon || "")});
      };

      class TabchatNotification {
        constructor(title, options) {
          this.title = title; this.body = (options && options.body) || "";
          this.onclick = null; this.onclose = null;
          notify(title, options);
        }
        close() { if (typeof this.onclose === "function") this.onclose(); }
        addEventListener() {}
        removeEventListener() {}
        static get permission() { return "granted"; }
        static requestPermission(cb) {
          if (typeof cb === "function") cb("granted");
          return Promise.resolve("granted");
        }
      }
      try {
        Object.defineProperty(window, "Notification", {value: TabchatNotification, writable: true, configurable: true});
      } catch (e) { window.Notification = TabchatNotification; }

      if (window.ServiceWorkerRegistration) {
        ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
          notify(title, options);
          return Promise.resolve();
        };
      }

      if (window.top === window) {
        let last = null;
        const report = () => { if (document.title !== last) { last = document.title; post({type: "title", title: last}); } };
        const watch = () => {
          const t = document.querySelector("title");
          if (t) new MutationObserver(report).observe(t, {childList: true, characterData: true, subtree: true});
          report();
        };
        if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", watch); else watch();
        setInterval(report, 2000);
      }
    })();
    """#

    /// Evaluated after a page loads; returns a JSON string of `IconCandidate`s.
    static let iconQuery = #"""
    JSON.stringify(Array.from(document.querySelectorAll(
      'link[rel~="apple-touch-icon"], link[rel~="icon"], link[rel="shortcut icon"]'
    )).filter(l => l.href).map(l => ({
      href: l.href,
      apple: l.rel.indexOf("apple") >= 0,
      size: parseInt((l.getAttribute("sizes") || "0").split("x")[0], 10) || 0
    })))
    """#
}
