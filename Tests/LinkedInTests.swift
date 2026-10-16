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
        <h2 class="msg-entity-lockup__entity-title">Ada Example</h2></a></div>
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

    private static let linkedInProfile = """
    <html><body><main>
      <section><h1>Ada Example</h1>
        <div class="text-body-medium break-words">Engineer at Example Co</div>
        <span class="text-body-small inline t-black--light break-words">London, England</span>
        <a href="/in/ada-example/overlay/contact-info/">Contact info</a>
        <a href="https://www.linkedin.com/redir/redirect/?url=https%3A%2F%2Fada.example.com&amp;urlhash=x">ada.example.com</a>
      </section>
      <section><div id="about"></div><h2>About</h2>
        <div class="inline-show-more-text"><span aria-hidden="true">I build test fixtures.</span></div></section>
    </main></body></html>
    """

    private static let xProfile = """
    <html><body><div data-testid="primaryColumn">
      <div data-testid="UserName"><span>Ada Example</span>
    <span>@ada_example</span></div>
      <div data-testid="UserDescription">Writes code. <a href="https://t.co/abc">ada.example.com</a> <a href="/hashtag/x">#tests</a></div>
      <span data-testid="UserLocation">London</span>
      <a data-testid="UserUrl" href="https://t.co/def">example.org</a>
      <article data-testid="tweet"><div data-testid="socialContext">Pinned</div>
        <a href="/ada_example/status/111"><time datetime="2026-09-01T10:00:00.000Z">Sep 1</time></a>
        <div data-testid="tweetText">A pinned post</div></article>
      <article data-testid="tweet">
        <a href="/ada_example/status/222"><time datetime="2026-10-15T08:00:00.000Z">Oct 15</time></a>
        <div data-testid="tweetText">A newer post</div></article>
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

    func testProfileTargets() {
        func target(_ text: String) -> ProfileReader.Target? {
            if case let .success(found) = ProfileReader.target(text) {
                return found
            }
            return nil
        }
        XCTAssertEqual(
            target("https://www.linkedin.com/in/ada-example")?.url.absoluteString,
            "https://www.linkedin.com/in/ada-example/"
        )
        XCTAssertEqual(target("https://linkedin.com/in/ada-example/?trk=x")?.site, "linkedin")
        XCTAssertEqual(target("https://x.com/ada_example")?.url.absoluteString, "https://x.com/ada_example")
        XCTAssertEqual(target("https://x.com/ada_example/")?.site, "x")
        for refused in [
            "http://x.com/ada", "https://x.com/home", "https://x.com/ada/status/1", "https://twitter.com/ada",
            "https://www.linkedin.com/company/example", "https://www.linkedin.com/in/ada/details/skills/",
            "https://evil.example/in/ada", "https://x.com.evil.example/ada", "https://user@x.com/ada", "javascript:alert(1)",
            "https://www.linkedin.com/feed/"
        ] {
            XCTAssertNil(target(refused), refused)
        }
        if case let .failure(error) = ProfileReader.target("https://x.com/home") {
            XCTAssertEqual(error.code, .refused)
        }
    }

    @MainActor
    func testLinkedInProfile() async throws {
        let webView = try await load(Self.linkedInProfile, at: "https://www.linkedin.com/in/ada-example/")
        let target = try ProfileReader.Target(
            site: "linkedin",
            url: XCTUnwrap(URL(string: "https://www.linkedin.com/in/ada-example/"))
        )
        let json = try await PageReaders.run(ProfileReader.script, arguments: ["site": "linkedin", "max": 20000], in: webView)
        let profile = try XCTUnwrap(ProfileReader.response(json: json, target: target).profile)
        XCTAssertEqual(profile.name, "Ada Example")
        XCTAssertEqual(profile.headline, "Engineer at Example Co")
        XCTAssertEqual(profile.location, "London, England")
        XCTAssertEqual(profile.bio, "I build test fixtures.")
        XCTAssertEqual(profile.links, ["https://ada.example.com"])
        XCTAssertNil(profile.posts)
    }

    @MainActor
    func testXProfile() async throws {
        let webView = try await load(Self.xProfile, at: "https://x.com/ada_example")
        let target = try ProfileReader.Target(site: "x", url: XCTUnwrap(URL(string: "https://x.com/ada_example")))
        let json = try await PageReaders.run(ProfileReader.script, arguments: ["site": "x", "max": 20000], in: webView)
        let response = ProfileReader.response(json: json, target: target)
        XCTAssertEqual(response.untrusted, true)
        let profile = try XCTUnwrap(response.profile)
        XCTAssertEqual(profile.name, "Ada Example")
        XCTAssertEqual(profile.headline, "@ada_example")
        XCTAssertEqual(profile.location, "London")
        XCTAssertTrue(profile.bio.hasPrefix("Writes code."))
        XCTAssertEqual(profile.links, ["https://example.org", "https://ada.example.com"])
        XCTAssertEqual(
            profile.posts?.map(\.url),
            ["https://x.com/ada_example/status/111", "https://x.com/ada_example/status/222"]
        )
        XCTAssertEqual(profile.posts?.map(\.kind), ["pinned", nil])
        XCTAssertEqual(profile.posts?.last?.time, "2026-10-15T08:00:00.000Z")
    }

    @MainActor
    func testXCheckpoint() async throws {
        let webView = try await load(
            "<html><body>We noticed unusual activity on your account</body></html>",
            at: "https://x.com/account/access"
        )
        let target = try ProfileReader.Target(site: "x", url: XCTUnwrap(URL(string: "https://x.com/ada_example")))
        let json = try await PageReaders.run(ProfileReader.script, arguments: ["site": "x", "max": 20000], in: webView)
        XCTAssertEqual(ProfileReader.response(json: json, target: target).code, "checkpoint")
    }

    func testEveryFailureHasACode() {
        XCTAssertEqual(AgentResponse.failure("x").code, "failed")
        XCTAssertEqual(AgentResponse.failure("x", code: .rate).code, "rate")
    }
}
