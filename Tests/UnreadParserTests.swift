@testable import Tabchat
import XCTest

final class UnreadParserTests: XCTestCase {
    func testParsesLeadingCount() {
        XCTAssertEqual(UnreadParser.count(fromTitle: "(3) WhatsApp"), 3)
        XCTAssertEqual(UnreadParser.count(fromTitle: "(120) Inbox - Outlook"), 120)
        XCTAssertEqual(UnreadParser.count(fromTitle: "(0) Discord"), 0)
    }

    func testIgnoresTitlesWithoutLeadingCount() {
        XCTAssertEqual(UnreadParser.count(fromTitle: ""), 0)
        XCTAssertEqual(UnreadParser.count(fromTitle: "WhatsApp"), 0)
        XCTAssertEqual(UnreadParser.count(fromTitle: "Inbox (3)"), 0)
        XCTAssertEqual(UnreadParser.count(fromTitle: "(a) Chat"), 0)
        XCTAssertEqual(UnreadParser.count(fromTitle: "(12 Chat"), 0)
        XCTAssertEqual(UnreadParser.count(fromTitle: "()"), 0)
    }
}
