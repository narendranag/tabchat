@testable import Tabchat
import WebKit
import XCTest

/// LinkedIn's readers and the profile view against invented pages. Made-up names only: this repo is public.
final class LinkedInTests: XCTestCase {
    private static let inbox = """
    <html><head><title>Messaging | LinkedIn</title></head><body>
    <div class="msg-conversations-container"><ul class="msg-conversations-container__conversations-list">
      <li class="msg-conversation-listitem"><div class="msg-conversation-card__convo-item-container--unread">
        <a class="msg-conversation-listitem__link" href="/messaging/thread/2-AAAATHREADONE=/">
          <h3 class="msg-conversation-listitem__participant-names"><span>Ada Example</span></h3>
          <time class="msg-conversation-listitem__time-stamp">3:04 PM</time>
          <p class="msg-conversation-card__message-snippet">Ada: Are you free on Monday?</p>
          <span class="notification-badge__count">2</span>
        </a></div></li>
      <li class="msg-conversation-listitem"><div>
        <a class="msg-conversation-listitem__link" href="/messaging/thread/2-BBBBTHREADTWO=/">
          <h3 class="msg-conversation-listitem__participant-names"><span>Grace Sample</span></h3>
          <time>Oct 9</time>
          <p class="msg-conversation-card__message-snippet">You: Thanks!</p>
        </a></div></li>
      <li class="msg-conversation-listitem"><div>
        <a class="msg-conversation-listitem__link" href="/messaging/thread/2-CCCCTHREADTHREE=/">
          <h3 class="msg-conversation-listitem__participant-names"><span>Alan Test, Joan Demo</span></h3>
          <time>Dec 30, 2025</time>
          <p class="msg-conversation-card__message-snippet">Joan: See you there</p>
        </a></div></li>
    </ul></div>
    <div class="msg-thread">
      <div class="msg-title-bar"><a class="msg-thread__link-to-profile" href="https://www.linkedin.com/in/ada-example/">
        <dl><dt><h2>Ada Example</h2></dt><dd><div>Engineer at Example Co</div></dd></dl></a></div>
      <div class="msg-s-message-list"><ul class="msg-s-message-list-content">
        <li class="msg-s-message-list__event">
          <time class="msg-s-message-list__time-heading">Oct 14</time>
          <div class="msg-s-message-group__meta">
            <a class="msg-s-message-group__profile-link" href="/in/ada-example/">
              <span class="msg-s-message-group__name">Ada Example</span></a>
            <time class="msg-s-message-group__timestamp">3:04 PM</time></div>
          <div class="msg-s-event-listitem msg-s-event-listitem--other" data-event-urn="urn:li:msg_message:(t,m1)">
            <p class="msg-s-event-listitem__body">Hello there</p></div>
          <div class="msg-s-event-listitem msg-s-event-listitem--other" data-event-urn="urn:li:msg_message:(t,m2)">
            <p class="msg-s-event-listitem__body">Are you free on Monday?</p></div>
        </li>
        <li class="msg-s-message-list__event">
          <div class="msg-s-message-group__meta">
            <a class="msg-s-message-group__profile-link" href="/in/test-owner/">
              <span class="msg-s-message-group__name">Test Owner</span></a>
            <time class="msg-s-message-group__timestamp">16:20</time></div>
          <div class="msg-s-event-listitem" data-event-urn="urn:li:msg_message:(t,m3)">
            <p class="msg-s-event-listitem__body">Yes, see attached</p>
            <div class="ui-attachment"><span class="ui-attachment__filename">agenda.pdf</span></div></div>
        </li>
      </ul></div>
    </div></body></html>
    """

    @MainActor
    private func load(_ html: String, at url: String) async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1000, height: 2000))
        webView.loadHTMLString(html, baseURL: URL(string: url))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return webView
    }

    /// Thursday 16 October 2026, noon, local.
    private var nowMs: Double {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
        return date.timeIntervalSince1970 * 1000
    }

    private let thread = "https://www.linkedin.com/messaging/thread/2-AAAATHREADONE=/"

    @MainActor
    func testChatList() async throws {
        let webView = try await load(Self.inbox, at: thread)
        let json = try await PageReaders.run(LinkedInScripts.chats, arguments: ["nowMs": nowMs], in: webView)
        let chats = try XCTUnwrap(LinkedInScripts.chatsResponse(json: json, countsOnly: false, readOnly: false).chats)
        XCTAssertEqual(chats.map(\.name), ["Ada Example", "Grace Sample", "Alan Test, Joan Demo"])
        XCTAssertEqual(chats.map(\.unread), [2, 0, 0])
        XCTAssertEqual(chats.map(\.key), ["2-AAAATHREADONE=", "2-BBBBTHREADTWO=", "2-CCCCTHREADTHREE="])
        XCTAssertEqual(chats.map(\.date), ["2026-10-16", "2026-10-09", "2025-12-30"])
        XCTAssertEqual(chats.map(\.group), [false, false, true])
        XCTAssertEqual(chats[0].preview, "Ada: Are you free on Monday?")
        let unreadless = LinkedInScripts.chatsResponse(json: json, countsOnly: false, readOnly: true).chats
        XCTAssertEqual(unreadless?.count, 2)
        XCTAssertEqual(LinkedInScripts.chatsResponse(json: json, countsOnly: true, readOnly: false).counts?.withUnread, 1)
    }

    @MainActor
    func testChatsSinceStopsAtOlderDays() async throws {
        let webView = try await load(Self.inbox, at: thread)
        let json = try await PageReaders.run(
            LinkedInScripts.chatsSince, arguments: ["nowMs": nowMs, "sinceDay": "2026-10-01"], in: webView
        )
        let chats = LinkedInScripts.chatsResponse(json: json, countsOnly: false, readOnly: false).chats
        XCTAssertEqual(chats?.map(\.name), ["Ada Example", "Grace Sample"])
    }

    @MainActor
    func testMessages() async throws {
        let webView = try await load(Self.inbox, at: thread)
        let json = try await PageReaders.run(LinkedInScripts.messages, arguments: ["nowMs": nowMs], in: webView)
        let response = LinkedInScripts.messagesResponse(json: json)
        XCTAssertTrue(response.ok, response.error ?? "")
        XCTAssertEqual(response.untrusted, true)
        XCTAssertEqual(response.chat, "Ada Example")
        XCTAssertEqual(response.key, "2-AAAATHREADONE=")
        XCTAssertEqual(response.chatProfile, "https://www.linkedin.com/in/ada-example/")
        let messages = try XCTUnwrap(response.messages)
        XCTAssertEqual(
            messages.map(\.id),
            ["urn:li:msg_message:(t,m1)", "urn:li:msg_message:(t,m2)", "urn:li:msg_message:(t,m3)"]
        )
        XCTAssertEqual(messages.map(\.sender), ["Ada Example", "Ada Example", "Test Owner"])
        XCTAssertEqual(messages.map(\.direction), ["in", "in", "out"])
        XCTAssertEqual(messages.map(\.profile), [
            "https://www.linkedin.com/in/ada-example/", "https://www.linkedin.com/in/ada-example/",
            "https://www.linkedin.com/in/test-owner/"
        ])
        XCTAssertEqual(messages.map(\.date), ["2026-10-14", "2026-10-14", "2026-10-14"])
        XCTAssertEqual(messages.map(\.precision), ["minute", "minute", "minute"])
        let expected = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: 14,
            hour: 15,
            minute: 4
        )))
        XCTAssertEqual(AgentResponder.isoDate(messages[0].stamp), expected)
        XCTAssertTrue(messages[2].stamp.hasPrefix("2026-10-14T16:20"))
        XCTAssertEqual(messages[2].document?.name, "agenda.pdf")
        XCTAssertEqual(messages[1].text, "Are you free on Monday?")
    }

    @MainActor
    func testHistoryUntil() async throws {
        let webView = try await load(Self.inbox, at: thread)
        let json = try await PageReaders.run(LinkedInScripts.history, arguments: [
            "screens": 2, "until": "urn:li:msg_message:(t,m2)", "nowMs": nowMs
        ], in: webView)
        let response = LinkedInScripts.messagesResponse(json: json)
        XCTAssertEqual(response.messages?.map(\.id), ["urn:li:msg_message:(t,m3)"])
        XCTAssertEqual(LinkedInScripts.decode(json).reached, true)
    }

    @MainActor
    func testOpenRefusesUnreadAndFindsByKey() async throws {
        let webView = try await load(Self.inbox, at: thread)
        let refused = try await LinkedInScripts.decode(PageReaders.run(LinkedInScripts.open, arguments: [
            "name": "Ada Example", "key": "", "ifRead": true, "nowMs": nowMs
        ], in: webView))
        XCTAssertFalse(refused.ok)
        XCTAssertEqual(refused.code, "refused")
        let missing = try await LinkedInScripts.decode(PageReaders.run(LinkedInScripts.open, arguments: [
            "name": "", "key": "2-ZZZZNOTHERE=", "ifRead": false, "nowMs": nowMs
        ], in: webView))
        XCTAssertEqual(missing.code, "not-found")
        XCTAssertEqual(missing.inList, false)
    }

    @MainActor
    func testCheckpointPageGivesCode() async throws {
        let webView = try await load(
            "<html><body>Let's do a quick security check</body></html>",
            at: "https://www.linkedin.com/checkpoint/challenge/123"
        )
        let response = try await LinkedInScripts.messagesResponse(json: PageReaders.run(
            LinkedInScripts.messages, arguments: ["nowMs": nowMs], in: webView
        ))
        XCTAssertFalse(response.ok)
        XCTAssertEqual(response.code, "checkpoint")
    }

    func testThreadIds() {
        XCTAssertEqual(LinkedInScripts.threadId("2-AAAATHREADONE="), "2-AAAATHREADONE=")
        XCTAssertEqual(
            LinkedInScripts.threadId("https://www.linkedin.com/messaging/thread/2-AAAATHREADONE%3D/"),
            "2-AAAATHREADONE="
        )
        XCTAssertNil(LinkedInScripts.threadId("Ada Example"))
        XCTAssertEqual(
            LinkedInScripts.threadURL("2-AB/C=")?.absoluteString,
            "https://www.linkedin.com/messaging/thread/2-AB%2FC=/"
        )
    }

    func testStamp() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        XCTAssertEqual(
            LinkedInScripts.stamp(date: "2026-10-14", time: "3:04 PM", calendar: calendar),
            "2026-10-14T15:04:00+05:30"
        )
        XCTAssertEqual(
            LinkedInScripts.stamp(date: "2026-10-14", time: "12:10 AM", calendar: calendar),
            "2026-10-14T00:10:00+05:30"
        )
        XCTAssertNil(LinkedInScripts.stamp(date: "2026-10-14", time: "", calendar: calendar))
    }

    func testEveryFailureHasACode() {
        XCTAssertEqual(AgentResponse.failure("x").code, "failed")
        XCTAssertEqual(AgentResponse.failure("x", code: .rate).code, "rate")
    }
}
