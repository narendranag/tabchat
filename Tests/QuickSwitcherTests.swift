@testable import Tabchat
import XCTest

final class QuickSwitcherTests: XCTestCase {
    private func titles(_ items: [PaletteItem]) -> [String] {
        items.map(\.title)
    }

    private let items: [PaletteItem] = [
        .tab(UUID(), title: "WhatsApp", unread: 3),
        .tab(UUID(), title: "Outlook (work)"),
        .tab(UUID(), title: "Discord"),
        .action(.newService),
        .action(.toggleSplit),
        .action(.pauseOneHour),
        .action(.settings)
    ]

    func testEmptyQueryKeepsTheOrder() {
        XCTAssertEqual(PaletteRanker.rank(items, query: ""), items)
        XCTAssertEqual(PaletteRanker.rank(items, query: "  "), items)
    }

    func testCaseInsensitiveSubstring() {
        XCTAssertEqual(titles(PaletteRanker.rank(items, query: "COLL")), [])
        XCTAssertEqual(titles(PaletteRanker.rank(items, query: "ISCO")), ["Discord"])
    }

    func testPrefixBeatsWordStartBeatsSubstring() {
        let list: [PaletteItem] = [.tab(UUID(), title: "Bookmark"), .tab(UUID(), title: "My Mark"), .tab(UUID(), title: "Mark")]
        XCTAssertEqual(titles(PaletteRanker.rank(list, query: "mark")), ["Mark", "My Mark", "Bookmark"])
    }

    func testFuzzyLettersInOrder() {
        XCTAssertEqual(titles(PaletteRanker.rank(items, query: "tsv")), ["Toggle Split View"])
        XCTAssertEqual(titles(PaletteRanker.rank(items, query: "wapp")), ["WhatsApp"])
        XCTAssertEqual(titles(PaletteRanker.rank(items, query: "zzz")), [])
    }

    func testTiesKeepTabsBeforeActions() {
        XCTAssertEqual(titles(PaletteRanker.rank(items, query: "s")).first, "Settings…")
        let list: [PaletteItem] = [.tab(UUID(), title: "Alpha"), .action(.reload), .tab(UUID(), title: "Alphb")]
        XCTAssertEqual(titles(PaletteRanker.rank(list, query: "al")), ["Alpha", "Alphb"])
    }

    func testArrowKeysStopAtTheEnds() {
        XCTAssertEqual(PaletteRanker.move(0, by: -1, count: 5), 0)
        XCTAssertEqual(PaletteRanker.move(4, by: 1, count: 5), 4)
        XCTAssertEqual(PaletteRanker.move(2, by: 1, count: 5), 3)
        XCTAssertEqual(PaletteRanker.move(3, by: 1, count: 0), 0)
    }

    func testItemIdsAreUnique() {
        let ids = PaletteAction.allCases.map { PaletteItem.action($0).id }
        XCTAssertEqual(Set(ids).count, PaletteAction.allCases.count)
    }
}
