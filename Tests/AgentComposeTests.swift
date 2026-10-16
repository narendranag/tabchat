@testable import Tabchat
import WebKit
import XCTest

/// `open` through search, `draft` and `send` against the invented page in `AgentActionTests`.
extension AgentActionTests {
    @MainActor
    func testOpenFindsAChatThroughSearchAndClearsIt() async throws {
        let webView = try await loadFixture()
        let result = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "🐒 Grace Sample"],
            in: webView
        ))
        XCTAssertTrue(result.ok, result.reason ?? "")
        XCTAssertEqual(result.chat, "🐒 Grace Sample")
        let search = try await webView.evaluateJavaScript("document.querySelector('#side input').value") as? String
        XCTAssertEqual(search, "")
        let missing = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "Grace"],
            in: webView
        ))
        XCTAssertEqual(missing.reason, "no chat with that exact name; search found: Grace Example | 🐒 Grace Sample")
        let own = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "Ada Owner"],
            in: webView
        ))
        XCTAssertEqual(own.chat, "Ada Owner (You)")
        let asked = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "Ada Owner (You)"],
            in: webView
        ))
        XCTAssertEqual(asked.chat, "Ada Owner (You)")
    }

    @MainActor
    private func compose(_ text: String, send: Bool, chat: String = "Ada Example", in webView: WKWebView) async throws
        -> WhatsAppScripts.Result {
        try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.compose, arguments: ["chat": chat, "text": text, "send": send], in: webView
        ))
    }

    @MainActor
    func testDraftTypesTheMessageAndStops() async throws {
        let webView = try await loadFixture()
        let result = try await compose("Hello Ada\nSee you at 3", send: false, in: webView)
        XCTAssertTrue(result.ok, result.reason ?? "")
        let box = try await webView.evaluateJavaScript("document.querySelector('footer [contenteditable]').innerText") as? String
        XCTAssertEqual(box?.replacingOccurrences(of: "\n", with: " "), "Hello Ada See you at 3")
        let sent = try await webView.evaluateJavaScript("document.body.dataset.sent || ''") as? String
        XCTAssertEqual(sent, "")
        let again = try await compose("Another", send: false, in: webView)
        XCTAssertEqual(again.reason, "the message box already has text; clear it first")
    }

    @MainActor
    func testSendTypesAndPressesSend() async throws {
        let webView = try await loadFixture()
        let wrong = try await compose("Hello", send: true, chat: "Grace Example", in: webView)
        XCTAssertEqual(wrong.reason, "a different chat is open")
        let result = try await compose("Hello Ada", send: true, in: webView)
        XCTAssertTrue(result.ok, result.reason ?? "")
        let sent = try await webView.evaluateJavaScript("document.body.dataset.sent") as? String
        XCTAssertEqual(sent, "Hello Ada")
    }

    func testMessageTextIsTrimmedAndBounded() {
        var request = AgentRequest(call: .send)
        XCTAssertEqual(AgentResponder.messageText(request), .failure(.coded("send needs --text", .refused)))
        request.text = "  On my way \n"
        XCTAssertEqual(AgentResponder.messageText(request), .success("On my way"))
        request.text = String(repeating: "a", count: AgentWire.maxMessageCharacters + 1)
        XCTAssertEqual(AgentResponder.messageText(request), .failure(.coded("messages are limited to 4000 characters", .refused)))
    }
}

/// Albums: every photo they show, one at a time.
extension AgentActionTests {
    @MainActor
    func testDownloadPicksAnAlbumPhotoAndCountsThem() async throws {
        let thumbs = (1 ... 2).map {
            #"<div role="button" id="p\#($0)"><div data-testid="image-thumb"></div></div>"#
        }.joined()
        let html = """
        <html><body><div id="main">
        <div data-id="album-A" data-testid="image-album" aria-label="Media album 6 photos">\(thumbs)</div>
        </div><script>
        for (const id of ["p1", "p2"]) document.getElementById(id).addEventListener("click", () => {
          const modal = document.createElement("div");
          modal.setAttribute("data-testid", "media-viewer-modal");
          modal.innerHTML = '<button aria-label="Download"></button><div aria-label="Close"></div>';
          modal.querySelector("button").addEventListener("click", () => { document.body.dataset.downloaded = id; });
          modal.querySelector("[aria-label=Close]").addEventListener("click", () => modal.remove());
          document.body.appendChild(modal);
        });
        </script></body></html>
        """
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let second = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.download, arguments: ["id": "album-A", "index": 1], in: webView
        ))
        XCTAssertTrue(second.ok, second.reason ?? "")
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(second.total, 6)
        let pressed = try await webView.evaluateJavaScript("document.body.dataset.downloaded") as? String
        XCTAssertEqual(pressed, "p2")
        let beyond = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.download, arguments: ["id": "album-A", "index": 2], in: webView
        ))
        XCTAssertEqual(beyond.reason, "that message has no item 2")
    }
}

/// What the CRM's nightly run asks for: only what's new, and only chats it may open.
extension AgentActionTests {
    @MainActor
    func testHistoryUntilReturnsOnlyNewerMessages() async throws {
        let rows = (1 ... 12).map {
            #"<div style="height:60px"><div data-id="H\#($0)"><span data-testid="selectable-text">Note \#($0)</span>"#
                + #"<div data-testid="msg-meta">1:\#(String(format: "%02d", $0)) pm</div></div></div>"#
        }.joined()
        let html = """
        <html><body><div id="main"><header><span data-testid="conversation-info-header-chat-title">Ada Example</span></header>
        <div id="pane" style="height:200px;overflow-y:auto">\(rows)</div></div>
        <script>const p = document.getElementById("pane"); p.scrollTop = p.scrollHeight;</script></body></html>
        """
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let json = try await PageReaders.run(WhatsAppScripts.history, arguments: ["screens": 20, "until": "H8"], in: webView)
        XCTAssertEqual(WhatsAppScripts.messagesResponse(json: json).messages?.map(\.id), ["H9", "H10", "H11", "H12"])
        XCTAssertEqual(WhatsAppScripts.decode(json).reached, true)
        let missing = try await PageReaders.run(WhatsAppScripts.history, arguments: ["screens": 2, "until": "NOPE"], in: webView)
        XCTAssertEqual(WhatsAppScripts.decode(missing).reached, false)
    }

    func testChatsReadOnlyAndDated() {
        let json = #"{"ok":true,"chats":[{"name":"Ada","preview":"","time":"","unread":2},"#
            + #"{"name":"Grace","preview":"","time":"","unread":0}]}"#
        XCTAssertEqual(PageReaders.chatsResponse(json: json, countsOnly: false, readOnly: true).chats?.map(\.name), ["Grace"])
        XCTAssertEqual(PageReaders.chatsResponse(json: json, countsOnly: false).chats?.count, 2)
    }

    @MainActor
    func testOpenIfReadLeavesUnreadChatsAlone() async throws {
        let webView = try await loadFixture()
        let refused = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open, arguments: ["name": "Grace Example", "ifRead": true], in: webView
        ))
        XCTAssertEqual(refused.reason, "that chat has unread messages; not opened")
        let header = try await webView.evaluateJavaScript(
            "document.querySelector('[data-testid=conversation-info-header-chat-title]').textContent"
        ) as? String
        XCTAssertEqual(header, "Ada Example")
        let opened = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open, arguments: ["name": "Grace Example", "ifRead": false], in: webView
        ))
        XCTAssertEqual(opened.chat, "Grace Example")
    }
}

extension AgentActionTests {
    func testSinceAcceptsLocalTimesAndDates() throws {
        XCTAssertNotNil(AgentResponder.isoDate("2026-10-01T00:00:00Z"))
        XCTAssertNotNil(AgentResponder.isoDate("2026-10-01T00:00:00.000+05:30"))
        let local = try XCTUnwrap(AgentResponder.isoDate("2026-10-01T09:30:00"))
        XCTAssertEqual(Calendar.current.component(.hour, from: local), 9)
        XCTAssertNotNil(AgentResponder.isoDate("2026-10-01T09:30"))
        XCTAssertNotNil(AgentResponder.isoDate("2026-10-01"))
        XCTAssertNil(AgentResponder.isoDate("yesterday"))
    }
}
