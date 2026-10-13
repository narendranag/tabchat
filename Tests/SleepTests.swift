@testable import Tabchat
import XCTest

final class SleepTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ count: Double) -> Date {
        start.addingTimeInterval(count * 60)
    }

    private func tabs() -> [Tab] {
        var state = AppState()
        for id in ["whatsapp", "reddit", "x"] {
            state.addTab(service: ServiceCatalog.service(id: id)!)
        }
        return state.tabs
    }

    private func due(_ clock: SleepClock, _ tabs: [Tab], visible: Set<UUID> = [], after: Int = 30, at: Date) -> [UUID] {
        clock.due(tabs: tabs, awake: { _ in true }, visible: visible, afterMinutes: after, now: at)
    }

    func testChatServicesDefaultToNoSleep() {
        let tabs = tabs()
        XCTAssertEqual(tabs.map(\.allowSleep), [false, true, true])
        for id in ["discord", "teams", "outlook-work", "outlook-personal"] {
            XCTAssertFalse(ServiceCatalog.allowsSleepByDefault(serviceId: id))
        }
        XCTAssertTrue(ServiceCatalog.allowsSleepByDefault(serviceId: "onedrive"))
    }

    func testTabSleepsOnlyAfterTheIdleTime() {
        let tabs = tabs()
        var clock = SleepClock()
        clock.touch(tabs.map(\.id), at: start)
        XCTAssertEqual(due(clock, tabs, at: minutes(29.9)), [])
        XCTAssertEqual(due(clock, tabs, at: minutes(30)), [tabs[1].id, tabs[2].id])
    }

    func testSelectedTabsAndNeverSettingDoNotSleep() {
        let tabs = tabs()
        var clock = SleepClock()
        clock.touch(tabs.map(\.id), at: start)
        XCTAssertEqual(due(clock, tabs, visible: [tabs[1].id], at: minutes(90)), [tabs[2].id])
        XCTAssertEqual(due(clock, tabs, after: 0, at: minutes(900)), [])
    }

    func testTouchingRestartsTheTimer() {
        let tabs = tabs()
        var clock = SleepClock()
        clock.touch(tabs.map(\.id), at: start)
        clock.touch([tabs[1].id], at: minutes(20))
        XCTAssertEqual(due(clock, tabs, at: minutes(35)), [tabs[2].id])
        XCTAssertEqual(due(clock, tabs, at: minutes(50)), [tabs[1].id, tabs[2].id])
    }

    func testUntrackedAwakeAndEphemeralTabsAreSkipped() {
        var tabs = tabs()
        var clock = SleepClock()
        XCTAssertEqual(due(clock, tabs, at: minutes(500)), [])
        clock.track(tabs.map(\.id), at: start)
        clock.track(tabs.map(\.id), at: minutes(100))
        XCTAssertEqual(clock.lastShown[tabs[0].id], start)
        tabs[1].incognito = true
        let asleep = tabs[2].id
        let result = clock.due(tabs: tabs, awake: { $0 != asleep }, visible: [], afterMinutes: 15, now: minutes(60))
        XCTAssertEqual(result, [])
        clock.forget(tabs[0].id)
        XCTAssertNil(clock.lastShown[tabs[0].id])
    }

    func testSleepOptions() {
        XCTAssertEqual(SleepAfter.options, [0, 15, 30, 60])
        XCTAssertEqual(SleepAfter.label(0), "Never")
        XCTAssertEqual(SleepAfter.label(15), "15 minutes")
        XCTAssertEqual(AppSettings().sleepAfterMinutes, 30)
    }
}
