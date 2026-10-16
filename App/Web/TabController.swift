import AppKit
import Observation
import WebKit

/// Owns the web view of one tab and everything WebKit asks of its delegates.
@MainActor
@Observable
final class TabController: NSObject {
    let tab: Tab
    let webView: WKWebView

    private(set) var loadError: String?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    var findVisible = false
    var findText = ""
    private(set) var findMissed = false

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []
    @ObservationIgnored private var popups: [ObjectIdentifier: NSWindow] = [:]
    @ObservationIgnored private var downloadNames: [ObjectIdentifier: URL] = [:]
    /// Set by the agent API while it waits for a download it started; see `AgentDownloadSlot`.
    @ObservationIgnored var agentDownload: AgentDownloadSlot?

    init(tab: Tab, dataStore: WKWebsiteDataStore, model: AppModel) {
        self.tab = tab
        self.model = model

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.userContentController.addUserScript(
            WKUserScript(source: BridgeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        // The handler is added after super.init so `self` can be passed; the script only runs once pages load.
        config.userContentController.add(MessageForwarder(self), name: BridgeScript.handlerName)
        webView.customUserAgent = safariUserAgent
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
            webView.isInspectable = true
        #endif
        webView.uiDelegate = self
        webView.navigationDelegate = self
        observe()
    }

    private func observe() {
        // KVO callbacks arrive on the main thread but are not annotated as such.
        observers = [
            webView.observe(\.title) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.titleChanged(wv.title ?? "") }
            },
            webView.observe(\.canGoBack) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward }
            },
            webView.observe(\.isLoading) { [weak self] wv, _ in
                MainActor.assumeIsolated { self?.isLoading = wv.isLoading }
            }
        ]
    }

    func tearDown() {
        observers.removeAll()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.stopLoading()
        webView.removeFromSuperview()
        for window in popups.values {
            window.close()
        }
        popups.removeAll()
    }

    // MARK: Navigation

    /// The saved address (a tab that slept or was duplicated) if there is one, else the start page.
    func loadStartPage() {
        guard let url = tab.lastURL.flatMap(URLInput.normalize) ?? tab.startURL else { return }
        webView.load(URLRequest(url: url))
    }

    func goHome() {
        guard let url = tab.startURL else { return }
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func retry() {
        if webView.url == nil {
            loadStartPage()
        } else {
            webView.reload()
        }
    }

    private var referenceURLs: [URL] {
        [tab.startURL, webView.url].compactMap(\.self)
    }

    // MARK: Find on page

    func showFind() {
        findVisible = true
    }

    func hideFind() {
        findVisible = false
        findMissed = false
        webView.evaluateJavaScript("window.getSelection().removeAllRanges()", completionHandler: nil)
        webView.window?.makeFirstResponder(webView)
    }

    func find(backwards: Bool = false) {
        guard !findText.isEmpty else {
            findMissed = false
            return
        }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        let text = findText
        Task { [weak self, webView] in
            let result = try? await webView.find(text, configuration: config)
            self?.findMissed = !(result?.matchFound ?? false)
        }
    }

    // MARK: Reports

    private func titleChanged(_ title: String) {
        model?.setUnread(tab.id, UnreadParser.parse(title: title))
    }

    fileprivate func handle(message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "title":
            if message.webView === webView {
                titleChanged(body["title"] as? String ?? "")
            }
        case "notification":
            model?.postNotification(title: body["title"] as? String ?? "", body: body["body"] as? String ?? "", from: tab)
        default:
            break
        }
    }

    private func discoverIcon() {
        guard let model, let page = webView.url, let start = tab.startURL,
              LinkPolicy.decision(for: page, tabURLs: [start]) == .inApp,
              model.icons[tab.iconKey] == nil
        else { return }
        let key = tab.iconKey
        Task { [webView] in
            let json = try? await webView.evaluateJavaScript(BridgeScript.iconQuery) as? String
            let found = json.flatMap { try? JSONDecoder().decode([IconCandidate].self, from: Data($0.utf8)) } ?? []
            await model.fetchIcon(candidates: IconCandidate.ranked(found, pageURL: page), key: key)
        }
    }

    private func fail(_ error: Error) {
        let nsError = error as NSError
        // Cancelled loads and "frame load interrupted" (a navigation turned into a download) are not failures.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return
        }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            return
        }
        loadError = error.localizedDescription
    }
}

/// WKUserContentController retains its handlers; this weak hop avoids a retain cycle with the controller.
private final class MessageForwarder: NSObject, WKScriptMessageHandler {
    private weak var target: TabController?

    @MainActor init(_ target: TabController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { target?.handle(message: message) }
    }
}

// MARK: - WKUIDelegate

extension TabController: WKUIDelegate {
    func webView(
        _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        // The user opened this site themselves; macOS still asks once for the camera and microphone.
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            let preference = model?.state.settings.linkTarget ?? .defaultBrowser
            let route = LinkPolicy.route(for: url, tabURLs: referenceURLs, preference: preference)
            if route != .popup {
                model?.openExternal(url, route: route, from: tab)
                return nil
            }
        }
        // Sign-in popups share the opener's configuration (and so its data store), which OAuth needs.
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 700), configuration: configuration)
        popup.customUserAgent = safariUserAgent
        #if DEBUG
            popup.isInspectable = true
        #endif
        popup.uiDelegate = self
        popup.navigationDelegate = self
        let window = NSWindow(
            contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.title = tab.displayName
        window.center()
        window.makeKeyAndOrderFront(nil)
        popups[ObjectIdentifier(popup)] = window
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.removeValue(forKey: ObjectIdentifier(webView))?.close()
    }

    func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) }
    }

    func webView(
        _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(
        _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

// MARK: - WKNavigationDelegate

extension TabController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === self.webView {
            loadError = nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView {
            loadError = nil
            discoverIcon()
        } else if let title = webView.title, !title.isEmpty {
            popups[ObjectIdentifier(webView)]?.title = title
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView {
            fail(error)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if webView === self.webView {
            fail(error)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if webView === self.webView {
            webView.reload()
        }
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
}

// MARK: - WKDownloadDelegate

extension TabController: WKDownloadDelegate {
    func download(
        _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        var directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        if let slot = agentDownload, slot.download == nil {
            slot.download = ObjectIdentifier(download)
            slot.source = response.url
            if let reason = slot.check?(response) {
                slot.failure = reason
                completionHandler(nil)
                return
            }
            directory = slot.directory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let destination = DownloadNaming.uniqueURL(in: directory, filename: suggestedFilename) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        downloadNames[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let slot = agentDownload, slot.download == ObjectIdentifier(download),
           let url = downloadNames.removeValue(forKey: ObjectIdentifier(download)) {
            AgentDownloadSlot.quarantine(url, source: slot.source)
            slot.finished = url
            model?.showToast("Agent downloaded \(url.lastPathComponent)")
        } else if let url = downloadNames.removeValue(forKey: ObjectIdentifier(download)) {
            model?.showToast("Downloaded \(url.lastPathComponent)")
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadNames[ObjectIdentifier(download)] = nil
        if let slot = agentDownload, slot.download == ObjectIdentifier(download) {
            // A file the slot refused is cancelled; keep the slot's reason, not "cancelled".
            slot.failure = slot.failure ?? error.localizedDescription
        }
        model?.showToast("Download failed: \(error.localizedDescription)")
    }
}
