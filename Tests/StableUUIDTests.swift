@testable import Tabchat
import XCTest

final class StableUUIDTests: XCTestCase {
    func testSameNameGivesSameUUID() {
        XCTAssertEqual(StableUUID.make("whatsapp-1"), StableUUID.make("whatsapp-1"))
    }

    func testDifferentNamesGiveDifferentUUIDs() {
        XCTAssertNotEqual(StableUUID.make("whatsapp-1"), StableUUID.make("whatsapp-2"))
    }

    func testIsVersion5() {
        XCTAssertEqual(StableUUID.make("x").uuidString.dropFirst(14).first, "5")
    }

    func testProfileUsesStableID() {
        XCTAssertEqual(Profile(id: "a", name: "A").dataStoreID, StableUUID.make("a"))
    }
}
