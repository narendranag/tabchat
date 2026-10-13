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

final class UnreadIndicatorTests: XCTestCase {
    func testCountWins() {
        XCTAssertEqual(UnreadParser.parse(title: "(3) WhatsApp"), Unread(count: 3, dot: false))
    }

    func testDotPrefixes() {
        XCTAssertEqual(UnreadParser.parse(title: "• Discord"), Unread(count: 0, dot: true))
        XCTAssertEqual(UnreadParser.parse(title: "* Inbox"), Unread(count: 0, dot: true))
        XCTAssertEqual(UnreadParser.parse(title: "  •Chat"), Unread(count: 0, dot: true))
    }

    func testNoUnread() {
        XCTAssertEqual(UnreadParser.parse(title: "Inbox * work"), .none)
        XCTAssertEqual(UnreadParser.parse(title: "(0) Discord"), .none)
        XCTAssertFalse(Unread.none.hasUnread)
    }

    func testSummary() {
        let values = [Unread(count: 2), Unread(count: 0, dot: true), .none, Unread(count: 5)]
        XCTAssertEqual(UnreadSummary.total(values), 7)
        XCTAssertTrue(UnreadSummary.anyUnread(values))
        XCTAssertEqual(UnreadSummary.dockLabel(total: 7), "7")
        XCTAssertNil(UnreadSummary.dockLabel(total: 0))
        // A dot alone lights the menu bar but leaves the Dock badge empty.
        let dotOnly = [Unread(count: 0, dot: true)]
        XCTAssertTrue(UnreadSummary.anyUnread(dotOnly))
        XCTAssertNil(UnreadSummary.dockLabel(total: UnreadSummary.total(dotOnly)))
        XCTAssertFalse(UnreadSummary.anyUnread([Unread]()))
    }

    func testMenuTitle() {
        XCTAssertEqual(UnreadSummary.menuTitle(name: "Teams", unread: Unread(count: 4)), "Teams  (4)")
        XCTAssertEqual(UnreadSummary.menuTitle(name: "Teams", unread: Unread(count: 0, dot: true)), "Teams  •")
        XCTAssertEqual(UnreadSummary.menuTitle(name: "Teams", unread: .none), "Teams")
    }
}
