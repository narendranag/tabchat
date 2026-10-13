import AppKit
import WebKit
import UserNotifications

/// JS injected at document start in every frame: fake Notification API + title reporting.
let bridgeJS = """
(function () {
  if (window.__tabchatBridge) return;
  window.__tabchatBridge = true;
  const post = (m) => { try { window.webkit.messageHandlers.tabchat.postMessage(m); } catch (e) {} };

  class TabchatNotification {
    constructor(title, options) {
      options = options || {};
      this.title = title; this.body = options.body || ""; this.tag = options.tag || "";
      this.icon = options.icon || ""; this.onclick = null; this.onclose = null;
      post({type: "notification", title: String(title), body: String(this.body),
            tag: String(this.tag), icon: String(this.icon)});
    }
    close() { if (typeof this.onclose === "function") this.onclose(); }
    addEventListener() {} removeEventListener() {}
    static get permission() { return "granted"; }
    static requestPermission(cb) {
      if (typeof cb === "function") cb("granted");
      return Promise.resolve("granted");
    }
  }
  try { Object.defineProperty(window, "Notification", {value: TabchatNotification, writable: true, configurable: true}); }
  catch (e) { window.Notification = TabchatNotification; }

  if (window.ServiceWorkerRegistration) {
    ServiceWorkerRegistration.prototype.showNotification = function (title, options) {
      options = options || {};
      post({type: "notification", title: String(title), body: String(options.body || ""),
            tag: String(options.tag || ""), icon: String(options.icon || "")});
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
"""

@MainActor
final class TabController: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    let tab: TabSpec
    unowned let model: Model
    let webView: WKWebView
    private var observers: [NSKeyValueObservation] = []
    private var popups: [ObjectIdentifier: NSWindow] = [:]

    init(tab: TabSpec, store: WKWebsiteDataStore, model: Model) {
        self.tab = tab
        self.model = model
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.mediaTypesRequiringUserActionForPlayback = []
        let script = WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        config.userContentController.add(self, name: "tabchat")
        webView.customUserAgent = safariUserAgent
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.uiDelegate = self
        webView.navigationDelegate = self
        let id = tab.id
        observers.append(webView.observe(\.title) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.titleChanged(wv.title ?? "", source: "KVO") }
        })
        observers.append(webView.observe(\.url) { [weak self] wv, _ in
            MainActor.assumeIsolated { self?.model.urls[id] = wv.url?.absoluteString ?? "" }
        })
    }

    private func titleChanged(_ title: String, source: String) {
        var n = 0
        if let r = title.range(of: #"^\((\d+)\)"#, options: .regularExpression) {
            n = Int(title[r].dropFirst().dropLast()) ?? 0
        }
        if model.unread[tab.id] != n || source == "JS" {
            if model.unread[tab.id] != n { model.addLog("[\(tab.name)] title (\(source)): \"\(title)\" -> unread \(n)") }
        }
        model.setUnread(tab.id, n)
    }

    // MARK: JS bridge

    nonisolated func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "title":
                if message.webView === webView { titleChanged(body["title"] as? String ?? "", source: "JS") }
            case "notification":
                let title = body["title"] as? String ?? ""
                let text = body["body"] as? String ?? ""
                model.addLog("[\(tab.name)] notification: \"\(title)\" / \"\(text)\" tag=\(body["tag"] ?? "")")
                let content = UNMutableNotificationContent()
                content.title = title.isEmpty ? tab.name : title
                content.subtitle = tab.name
                content.body = text
                content.sound = .default
                content.userInfo = ["tab": tab.id]
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { err in
                    if let err { Task { @MainActor in self.model.addLog("notification post failed: \(err)") } }
                }
            default: break
            }
        }
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
        model.addLog("[\(tab.name)] media permission requested by \(origin.host) type=\(type.rawValue) -> grant")
        decisionHandler(.grant)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        model.addLog("[\(tab.name)] popup: \(navigationAction.request.url?.absoluteString ?? "(blank)")")
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 700), configuration: configuration)
        popup.customUserAgent = safariUserAgent
        popup.isInspectable = true
        popup.uiDelegate = self
        popup.navigationDelegate = self
        let win = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = popup
        win.title = "Sign in"
        win.center()
        win.makeKeyAndOrderFront(nil)
        popups[ObjectIdentifier(popup)] = win
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        model.addLog("[\(tab.name)] popup closed by page")
        if let win = popups.removeValue(forKey: ObjectIdentifier(webView)) { win.close() }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { resp in completionHandler(resp == .OK ? panel.urls : nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let a = NSAlert(); a.messageText = message; a.runModal(); completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let a = NSAlert(); a.messageText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        model.addLog("[\(tab.name)] navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        model.addLog("[\(tab.name)] provisional navigation failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        model.addLog("[\(tab.name)] web content process terminated")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var dest = dir.appendingPathComponent(suggestedFilename)
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)")
            i += 1
        }
        model.addLog("[\(tab.name)] download -> \(dest.path)")
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) { model.addLog("[\(tab.name)] download finished") }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        model.addLog("[\(tab.name)] download failed: \(error.localizedDescription)")
    }
}
