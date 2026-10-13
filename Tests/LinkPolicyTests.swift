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
