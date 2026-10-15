@testable import Tabchat
import WebKit
import XCTest

/// The agent API with made-up tabs, notifications and pages only. This repo is public.
final class AgentTests: XCTestCase {
    // swiftlint:disable:next large_tuple
    private func state(access: Bool = true) throws -> (AppState, Tab, Tab) {
        var state = AppState()
        var whatsapp = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "whatsapp")))
        let discord = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "discord")))
        state.settings.agentAccess = access
        state.tabs[0].agentReadable = true
        whatsapp.agentReadable = true
        return (state, whatsapp, discord)
    }

    private func item(_ tab: Tab, _ title: String, at time: Date) -> AgentFeedItem {
        AgentFeedItem(time: time, tab: tab.id.uuidString, service: tab.serviceId, title: title, body: "Hello")
    }

    // MARK: Who may read what

    func testOnlyTickedTabsAreReadable() throws {
        let (state, whatsapp, _) = try state()
        XCTAssertEqual(AgentResponder.readableTabs(state).map(\.id), [whatsapp.id])
    }

    func testNothingIsReadableWhenAccessIsOff() throws {
        let (state, _, _) = try state(access: false)
        XCTAssertTrue(AgentResponder.readableTabs(state).isEmpty)
    }

    func testIncognitoTabsAreNeverReadable() throws {
        var (state, _, _) = try state()
        let tab = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "discord")), incognito: true)
        let index = try XCTUnwrap(state.tabs.firstIndex { $0.id == tab.id })
        state.tabs[index].agentReadable = true
        XCTAssertFalse(AgentResponder.readableTabs(state).contains { $0.id == tab.id })
    }

    func testUnreadableTabIsRefused() throws {
        let (state, _, discord) = try state()
        let request = AgentRequest(call: .page, tab: discord.id.uuidString)
        XCTAssertEqual(AgentResponder.tab(for: request, in: state), .failure(.message("no readable tab with that id")))
    }

    func testTabsReportsUnreadAndLoaded() throws {
        let (state, whatsapp, _) = try state()
        let response = AgentResponder.tabs(state: state, unread: [whatsapp.id: Unread(count: 3)], loaded: [])
        XCTAssertEqual(response.tabs, [AgentTabInfo(
            id: whatsapp.id.uuidString, name: "WhatsApp", service: "whatsapp", unread: 3, unreadDot: false, loaded: false,
            actions: false
        )])
    }

    // MARK: Feed

    func testFeedKeepsOnlyReadableTabsAndRecentItems() throws {
        let (state, whatsapp, discord) = try state()
        let now = Date()
        var feed = AgentFeed()
        feed.append(item(whatsapp, "Ada", at: now.addingTimeInterval(-25 * 3600)))
        feed.append(item(whatsapp, "Test Group", at: now.addingTimeInterval(-120)))
        feed.append(item(discord, "Grace", at: now.addingTimeInterval(-60)))
        let all = AgentResponder.feed(request: AgentRequest(call: .feed), state: state, feed: feed, now: now)
        XCTAssertEqual(all.feed?.map(\.title), ["Test Group"])
        XCTAssertEqual(all.untrusted, true)
        let recent = AgentResponder.feed(
            request: AgentRequest(call: .feed, sinceSeconds: 60), state: state, feed: feed, now: now
        )
        XCTAssertEqual(recent.feed, [])
    }

    func testFeedIsBounded() throws {
        let (_, whatsapp, _) = try state()
        var feed = AgentFeed()
        for index in 0 ..< AgentFeed.capacity + 10 {
            feed.append(item(whatsapp, "\(index)", at: Date()))
        }
        XCTAssertEqual(feed.items.count, AgentFeed.capacity)
        XCTAssertEqual(feed.items.first?.title, "10")
    }

    // MARK: Settings file

    func testAgentKeysDefaultOffAndRoundTrip() throws {
        var (state, _, _) = try state()
        state.settings.agentAccess = true
        let decoded = try StateStore.decode(StateStore.encode(state))
        XCTAssertTrue(decoded.settings.agentAccess)
        XCTAssertTrue(decoded.tabs[0].agentReadable)
        XCTAssertFalse(decoded.tabs[1].agentReadable)
        XCTAssertFalse(AppSettings().agentAccess)
    }

    // MARK: Log

    func testLogLineHasNoContentAndTrims() {
        let now = Date()
        let line = AgentLog.line(.init(time: now, client: "tabchat-agent (42)", call: "feed", tab: nil, items: 2))
        XCTAssertTrue(line.hasSuffix("tabchat-agent (42)\tfeed\t-\t2 items\tok"))
        let old = AgentLog.line(.init(time: now.addingTimeInterval(-31 * 86400), client: "x", call: "tabs", items: 0))
        XCTAssertEqual(AgentLog.trimmed([Substring(old), Substring(line), "garbage"], now: now), [Substring(line)])
    }

    // MARK: MCP

    private func mcp(_ json: String, send: (AgentRequest) -> AgentResponse = { _ in AgentResponse(ok: true) })
        throws -> [String: Any] {
        let reply = try XCTUnwrap(AgentMCP.handle(Data(json.utf8), send: send))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
    }

    func testMCPInitializeAndListTools() throws {
        let initialize = try mcp(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#)
        let result = try XCTUnwrap(initialize["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, AgentMCP.protocolVersion)
        let list = try mcp(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        let tools = try XCTUnwrap((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(
            tools.compactMap { $0["name"] as? String },
            [
                "tabchat_tabs", "tabchat_status", "tabchat_feed", "tabchat_chats", "tabchat_page",
                "tabchat_messages", "tabchat_open", "tabchat_contact", "tabchat_download",
                "tabchat_draft", "tabchat_send", "tabchat_history"
            ]
        )
    }

    func testMCPNotificationsGetNoReply() {
        XCTAssertNil(AgentMCP.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)) { _ in
            AgentResponse(ok: true)
        })
    }

    func testMCPToolCallMapsArguments() throws {
        var seen: AgentRequest?
        let call = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","#
            + #""params":{"name":"tabchat_feed","arguments":{"tab":"T","since_minutes":5}}}"#
        let reply = try mcp(call) { request in
            seen = request
            return .failure("agent access is off")
        }
        XCTAssertEqual(seen, AgentRequest(call: .feed, tab: "T", sinceSeconds: 300))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    // MARK: Readers, against an invented page

    private static let fixture = """
    <html><head><title>(2) WhatsApp</title></head><body>
    <div id="pane-side"><div role="grid">
      <div role="row"><div><span title="Ada Example">Ada Example</span><div>10:21</div></div>
        <div><span title="See you at noon">See you at noon</span>
        <span aria-label="2 unread messages">2</span></div></div>
      <div role="row"><div><span title="Test Group">Test Group</span><div>Yesterday</div></div>
        <div><span title="Grace: the build is green">Grace: the build is green</span></div></div>
    </div></div>
    <p>Visible text</p>
    </body></html>
    """

    @MainActor
    private func loadFixture() async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://example.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return webView
    }

    @MainActor
    func testWhatsAppChatListReader() async throws {
        let webView = try await loadFixture()
        let script = try XCTUnwrap(PageReaders.chatList(serviceId: "whatsapp"))
        let json = try await PageReaders.run(script, in: webView)
        let now = Date()
        let response = PageReaders.chatsResponse(json: json, countsOnly: false, now: now)
        XCTAssertEqual(response.untrusted, true)
        XCTAssertEqual(response.chats, [
            AgentChat(
                name: "Ada Example", preview: "See you at noon", time: "10:21", unread: 2,
                date: WhatsAppScripts.date(ofDay: "Today", now: now)
            ),
            AgentChat(
                name: "Test Group", preview: "Grace: the build is green", time: "Yesterday", unread: 0,
                date: WhatsAppScripts.date(ofDay: "Yesterday", now: now)
            )
        ])
        let counts = PageReaders.chatsResponse(json: json, countsOnly: true)
        XCTAssertNil(counts.chats)
        XCTAssertEqual(counts.counts, AgentChatCounts(chats: 2, withPreview: 2, withTime: 2, withUnread: 1))
    }

    @MainActor
    func testPageTextReaderAndIsolation() async throws {
        let webView = try await loadFixture()
        let json = try await PageReaders.run(PageReaders.pageText, arguments: ["max": 12], in: webView)
        let page = try XCTUnwrap(PageReaders.pageResponse(json: json).page)
        XCTAssertEqual(page.title, "(2) WhatsApp")
        XCTAssertEqual(page.text.count, 12)
        XCTAssertTrue(page.truncated)
        // A global set in the agent world is invisible to the page's own scripts.
        _ = try await PageReaders.run("window.__agentMark = 1; return \"\";", in: webView)
        let seen = try await webView.evaluateJavaScript("typeof window.__agentMark") as? String
        XCTAssertEqual(seen, "undefined")
    }

    func testReaderFailureIsReportedNotGuessed() {
        let response = PageReaders.chatsResponse(json: #"{"ok":false,"reason":"no chat list on screen"}"#, countsOnly: false)
        XCTAssertEqual(response, .failure("no chat list on screen"))
        XCTAssertNil(PageReaders.chatList(serviceId: "teams"))
    }

    // MARK: Socket

    func testSocketRoundTripIsOwnerOnly() throws {
        let url = URL(fileURLWithPath: "/tmp/tc-\(UUID().uuidString.prefix(8)).sock")
        let server = AgentSocketServer(url: url) { line, _ in
            let request = try? AgentWire.decoder().decode(AgentRequest.self, from: line)
            return (try? AgentWire.line(AgentResponse(ok: request?.call == .tabs))) ?? Data()
        }
        try server.start()
        defer { server.stop() }
        let mode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        XCTAssertEqual(mode & 0o777, 0o600)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(url.path.utf8)) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        XCTAssertEqual(connected, 0)
        // A real client's request can arrive after the server starts reading; it must wait for it.
        Thread.sleep(forTimeInterval: 0.3)
        let line = try AgentWire.line(AgentRequest(call: .tabs))
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(fd, &buffer, buffer.count)
        let response = try AgentWire.decoder().decode(AgentResponse.self, from: Data(buffer[0 ..< max(count, 0)]))
        XCTAssertTrue(response.ok)
    }
}
