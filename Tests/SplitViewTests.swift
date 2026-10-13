@testable import Tabchat
import XCTest

final class SplitViewTests: XCTestCase {
    private func state() -> AppState {
        var state = AppState.firstRun()
        state.selectedTabId = state.tabs[0].id
        return state
    }

    func testOpenSplitPairsSelectedWithChosenTab() {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.openSplit(with: ids[2])
        XCTAssertEqual(state.split, SplitState(left: ids[0], right: ids[2], focus: .right))
        XCTAssertEqual(state.selectedTabId, ids[2])
        XCTAssertEqual(state.visibleIds, [ids[0], ids[2]])
    }

    func testOpenSplitOnSelectedTabUsesTheNextOne() {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.openSplit(with: ids[0])
        XCTAssertEqual(state.split?.right, ids[1])
        var single = AppState()
        single.addTab(service: ServiceCatalog.all[0])
        single.openSplit()
        XCTAssertNil(single.split)
    }

    func testSidebarClickReplacesTheFocusedSide() {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.openSplit(with: ids[1])
        state.select(ids[3])
        XCTAssertEqual(state.split, SplitState(left: ids[0], right: ids[3], focus: .right))
        // A tab that is already showing just takes the focus.
        state.select(ids[0])
        XCTAssertEqual(state.split?.focus, .left)
        XCTAssertEqual(state.selectedTabId, ids[0])
        state.select(ids[2])
        XCTAssertEqual(state.split, SplitState(left: ids[2], right: ids[3], focus: .left))
    }

    func testFocusSplitMovesSelection() {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.openSplit(with: ids[1])
        state.focusSplit(.left)
        XCTAssertEqual(state.selectedTabId, ids[0])
    }

    func testCloseKeepsTheFocusedTab() {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.toggleSplit()
        XCTAssertNotNil(state.split)
        state.toggleSplit()
        XCTAssertNil(state.split)
        XCTAssertEqual(state.selectedTabId, ids[1])
    }

    func testRemovingASplitTabClosesTheSplit() {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.openSplit(with: ids[1])
        state.removeTab(ids[1])
        XCTAssertNil(state.split)
        XCTAssertEqual(state.selectedTabId, ids[0])
    }

    func testRatioIsClampedBetween20And80Percent() {
        XCTAssertEqual(SplitMath.clamp(0.05), 0.2)
        XCTAssertEqual(SplitMath.clamp(0.95), 0.8)
        XCTAssertEqual(SplitMath.clamp(0.5), 0.5)
        XCTAssertEqual(SplitMath.clamp(.nan), 0.5)
        XCTAssertEqual(SplitMath.ratio(dragX: 0, total: 1000), 0.2)
        XCTAssertEqual(SplitMath.ratio(dragX: 5000, total: 1000), 0.8)
    }

    func testWidthsAccountForTheGutter() {
        let widths = SplitMath.widths(total: 1008, ratio: 0.5)
        XCTAssertEqual(widths.left, 500)
        XCTAssertEqual(widths.right, 500)
        XCTAssertEqual(SplitMath.ratio(dragX: 504, total: 1008), 0.5)
    }

    func testSplitSurvivesSaveAndLoadAndBadSplitIsDropped() throws {
        var state = state()
        let ids = state.tabs.map(\.id)
        state.openSplit(with: ids[1])
        state.settings.splitRatio = 0.35
        XCTAssertEqual(try StateStore.decode(StateStore.encode(state)), state)
        state.split = SplitState(left: ids[0], right: UUID())
        XCTAssertNil(try StateStore.decode(StateStore.encode(state)).split)
    }
}
