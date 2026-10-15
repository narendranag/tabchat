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
        XCTAssertEqual(AgentResponder.messageText(request), .failure(.message("send needs --text")))
        request.text = "  On my way \n"
        XCTAssertEqual(AgentResponder.messageText(request), .success("On my way"))
        request.text = String(repeating: "a", count: AgentWire.maxMessageCharacters + 1)
        XCTAssertEqual(AgentResponder.messageText(request), .failure(.message("messages are limited to 4000 characters")))
    }
}
