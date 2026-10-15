@testable import Tabchat
import WebKit
import XCTest

/// Discord's readers against an invented page. Made-up names only: this repo is public.
final class DiscordTests: XCTestCase {
    private static let fixture = """
    <html><head><title>(1) Discord | #general | Example Server</title></head><body>
    <nav aria-label="Private channels"><ul>
      <li><a href="/channels/@me">Friends</a></li>
      <li><a aria-label="Ada Example (direct message)" href="/channels/@me/111111111111111111">Ada Example</a></li>
      <li><a aria-label="unread, Grace Sample (direct message), Playing chess" href="/channels/@me/222222222222222222">Grace</a>
        <div class="numberBadge_x1">3</div></li>
      <li><a aria-label="Study Group (group message)" href="/channels/@me/333333333333333333">Study Group</a></li>
    </ul></nav>
    <ol data-list-id="chat-messages">
      <li id="chat-messages-9-1001"><div role="article"><div id="message-content-1001"><div data-accessibility="desaturate"></div>
        <div>Grace Sample joined. <time datetime="2026-10-14T09:00:00.000Z">10/14/26</time></div></div></div></li>
      <li id="chat-messages-9-1002"><div role="article">
        <h3><span id="message-username-1002"><span data-text="Ada Example">Ada Example</span></span>
          <time id="message-timestamp-1002" datetime="2026-10-14T09:05:00.000Z">— 10/14/26, 2:35 PM</time></h3>
        <div id="message-content-1002">Hello all</div></div></li>
      <li id="chat-messages-9-1003"><div role="article">
        <div id="message-reply-context-1003"><div id="message-content-1002">Hello all</div></div>
        <h3><span id="message-username-1003"><span data-text="Grace Sample">Grace Sample</span></span>
          <time datetime="2026-10-15T10:00:00.000Z">2:30 PM</time></h3>
        <div id="message-content-1003">Hi Ada</div>
        <div id="message-accessories-1003"><a href="https://cdn.discordapp.com/attachments/9/1/plan%20v2.pdf">plan v2.pdf</a></div>
      </div></li>
      <li id="chat-messages-9-1004"><div role="article"><time datetime="2026-10-15T10:01:00.000Z">2:31 PM</time>
        <div id="message-content-1004">Here is the photo</div>
        <div id="message-accessories-1004"><a data-role="img" href="https://cdn.discordapp.com/attachments/9/2/p.png"></a></div>
      </div></li>
    </ol></body></html>
    """

    @MainActor
    private func load() async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://discord.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return webView
    }

    @MainActor
    func testChatList() async throws {
        let webView = try await load()
        let script = try XCTUnwrap(PageReaders.chatList(serviceId: "discord"))
        let chats = try await PageReaders.chatsResponse(json: PageReaders.run(script, in: webView), countsOnly: false).chats
        XCTAssertEqual(chats?.map(\.name), ["Ada Example", "Grace Sample", "Study Group"])
        XCTAssertEqual(chats?.map(\.unread), [0, 3, 0])
        XCTAssertEqual(chats?.map(\.key), ["111111111111111111", "222222222222222222", "333333333333333333"])
        XCTAssertEqual(chats?.map(\.group), [false, false, true])
    }

    @MainActor
    func testMessages() async throws {
        let webView = try await load()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let response = try await DiscordScripts.messagesResponse(
            json: PageReaders.run(DiscordScripts.messages, in: webView), calendar: calendar, locale: Locale(identifier: "en_GB")
        )
        XCTAssertEqual(response.chat, "#general | Example Server")
        let messages = try XCTUnwrap(response.messages)
        XCTAssertEqual(messages.map(\.id), ["1001", "1002", "1003", "1004"])
        XCTAssertEqual(messages.map(\.sender), ["", "Ada Example", "Grace Sample", "Grace Sample"])
        XCTAssertEqual(messages.map(\.text), ["Grace Sample joined. 10/14/26", "Hello all", "Hi Ada", "Here is the photo"])
        XCTAssertEqual(messages[2].document?.name, "plan v2.pdf")
        XCTAssertEqual(messages[3].media, "image")
        XCTAssertEqual(messages.map(\.date), ["14/10/2026", "14/10/2026", "15/10/2026", "15/10/2026"])
        XCTAssertEqual(messages[1].time, "10/14/26, 2:35 PM")
    }
}
