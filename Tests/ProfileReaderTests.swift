@testable import Tabchat
import WebKit
import XCTest

/// `profile` against invented LinkedIn and X pages. Made-up names only: this repo is public.
final class ProfileReaderTests: XCTestCase {
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

    /// The newer layout (2026): `componentkey` cards, the name an h2, the rest plain paragraphs.
    private static let linkedInCards = """
    <html><body><main><section aria-label="Primary content">
      <div componentkey="com.linkedin.sdui.profile.card.refTESTTopcard"><section>
        <a href="/in/ada-example/verifications"><div><h2>Ada Example</h2></div></a>
        <p>Engineer at Example Co</p>
        <p>Example Co + 1 more</p>
        <div><p>London, England</p><p>·</p><p><a href="/in/ada-example/overlay/contact-info/">Contact info</a></p></div>
        <a href="/search/results/people/?connectionOf=x"><p>500+ connections</p></a>
      </section></div>
      <div componentkey="com.linkedin.sdui.profile.card.refTESTAbout"><section>
        <h2>About</h2><div><p>I build test fixtures.</p></div><span>…see more</span></section></div>
    </section></main></body></html>
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
    func testLinkedInProfileCards() async throws {
        let webView = try await load(Self.linkedInCards, at: "https://www.linkedin.com/in/ada-example/")
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
}
