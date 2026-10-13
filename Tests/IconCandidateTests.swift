@testable import Tabchat
import XCTest

final class IconCandidateTests: XCTestCase {
    func testRanksAppleIconsThenLargestThenFavicon() throws {
        let page = try XCTUnwrap(URL(string: "https://example.com/app/"))
        let found = [
            IconCandidate(href: "https://example.com/16.png", apple: false, size: 16),
            IconCandidate(href: "/touch.png", apple: true, size: 0),
            IconCandidate(href: "https://example.com/64.png", apple: false, size: 64)
        ]
        let urls = IconCandidate.ranked(found, pageURL: page).map(\.absoluteString)
        XCTAssertEqual(urls, [
            "https://example.com/touch.png", "https://example.com/64.png",
            "https://example.com/16.png", "https://example.com/favicon.ico"
        ])
    }
}
