@testable import Tabchat
import XCTest

final class LinkPolicyTests: XCTestCase {
    private let whatsapp = [URL(string: "https://web.whatsapp.com")!]
    private let teams = [URL(string: "https://teams.microsoft.com")!]

    private func decide(_ url: String, _ tab: [URL]) -> LinkPolicy.Decision {
        LinkPolicy.decision(for: URL(string: url)!, tabURLs: tab)
    }

    func testSameSiteStaysInApp() {
        XCTAssertEqual(decide("https://web.whatsapp.com/send?phone=1", whatsapp), .inApp)
        XCTAssertEqual(decide("https://teams.microsoft.com/l/meetup-join/x", teams), .inApp)
    }

    func testRelatedDomainsOfOneProductStayInApp() {
        XCTAssertEqual(decide("https://contoso.sharepoint.com/doc", teams), .inApp)
        XCTAssertEqual(decide("https://www.office.com/", teams), .inApp)
    }

    func testOtherSiteOpensExternally() {
        XCTAssertEqual(decide("https://example.com/article", whatsapp), .external)
        XCTAssertEqual(decide("mailto:a@b.com", whatsapp), .external)
    }

    func testSignInHostsStayInApp() {
        XCTAssertEqual(decide("https://login.microsoftonline.com/common/oauth2", whatsapp), .inApp)
        XCTAssertEqual(decide("https://login.live.com/", whatsapp), .inApp)
        XCTAssertEqual(decide("https://accounts.google.com/o/oauth2", whatsapp), .inApp)
        XCTAssertEqual(decide("https://discord.com/oauth2/authorize", whatsapp), .inApp)
        XCTAssertEqual(decide("https://discord.com/channels/1", whatsapp), .external)
    }

    func testBlankPopupStaysInApp() {
        XCTAssertEqual(decide("about:blank", whatsapp), .inApp)
    }

    func testRegistrableDomainWithSecondLevelSuffix() {
        XCTAssertEqual(LinkPolicy.siteKey(host: "learn.school.ac.uk"), "school.ac.uk")
        XCTAssertEqual(LinkPolicy.siteKey(host: "a.b.example.com"), "example.com")
    }
}

final class SocialServiceTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testXAndRedditGroupsAndProfiles() throws {
        let home = try url("https://x.com/home")
        let reddit = try url("https://www.reddit.com/")
        XCTAssertEqual(try LinkPolicy.decision(for: url("https://t.co/abc"), tabURLs: [home]), .inApp)
        XCTAssertEqual(try LinkPolicy.decision(for: url("https://twitter.com/a"), tabURLs: [home]), .inApp)
        XCTAssertEqual(try LinkPolicy.decision(for: url("https://redd.it/abc"), tabURLs: [reddit]), .inApp)
        XCTAssertEqual(try LinkPolicy.decision(for: url("https://example.com"), tabURLs: [home]), .external)
        var state = AppState()
        let redditService = try XCTUnwrap(ServiceCatalog.service(id: "reddit"))
        let first = state.addTab(service: redditService)
        let second = state.addTab(service: redditService, newAccount: true)
        XCTAssertEqual(first.profileId, "reddit")
        XCTAssertNotEqual(first.profileId, second.profileId)
        XCTAssertEqual(try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "x"))).profileId, "x")
    }
}

final class LinkRouteTests: XCTestCase {
    private let tab = [URL(string: "https://web.whatsapp.com")!]

    private func route(_ url: String, _ preference: LinkTarget) -> LinkPolicy.Route {
        LinkPolicy.route(for: URL(string: url)!, tabURLs: tab, preference: preference)
    }

    func testSameSiteAndSignInAlwaysPopUpInApp() {
        XCTAssertEqual(route("https://web.whatsapp.com/x", .inTabchat), .popup)
        XCTAssertEqual(route("https://login.live.com/", .browser("org.mozilla.firefox")), .popup)
    }

    func testOtherSitesFollowThePreference() {
        XCTAssertEqual(route("https://example.com", .defaultBrowser), .defaultBrowser)
        XCTAssertEqual(route("https://example.com", .inTabchat), .temporaryTab)
        XCTAssertEqual(route("https://example.com", .browser("org.mozilla.firefox")), .browser("org.mozilla.firefox"))
    }

    func testNonWebLinksIgnoreThePreference() {
        XCTAssertEqual(route("mailto:a@b.com", .inTabchat), .defaultBrowser)
        XCTAssertEqual(route("tel:123", .browser("org.mozilla.firefox")), .defaultBrowser)
    }

    func testLinkTargetStorage() throws {
        for target in [LinkTarget.defaultBrowser, .inTabchat, .browser("com.apple.Safari")] {
            XCTAssertEqual(LinkTarget(storage: target.storage), target)
            let data = try JSONEncoder().encode([target])
            XCTAssertEqual(try JSONDecoder().decode([LinkTarget].self, from: data), [target])
        }
        XCTAssertEqual(LinkTarget(storage: ""), .defaultBrowser)
    }
}
