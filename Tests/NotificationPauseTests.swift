@testable import Tabchat
import XCTest

final class NotificationPauseTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: min))!
    }

    func testOneHour() {
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 10, 13, 15, 30)
        let pause = NotificationPause.make(.oneHour, now: now, calendar: cal)
        XCTAssertEqual(pause.until, date(cal, 2026, 10, 13, 16, 30))
        XCTAssertTrue(pause.isPaused(at: now))
        XCTAssertFalse(pause.isPaused(at: date(cal, 2026, 10, 13, 16, 30)))
        XCTAssertEqual(pause.status(now: now, calendar: cal, locale: Locale(identifier: "en_GB")), "Paused until 16:30")
    }

    func testTomorrowMorningCrossesMidnight() {
        let cal = calendar("America/New_York")
        let evening = date(cal, 2026, 12, 31, 23, 30)
        let pause = NotificationPause.make(.untilTomorrowMorning, now: evening, calendar: cal)
        XCTAssertEqual(pause.until, date(cal, 2027, 1, 1, 8))
        XCTAssertEqual(
            pause.status(now: evening, calendar: cal, locale: Locale(identifier: "en_GB")), "Paused until tomorrow 08:00"
        )
    }

    func testTomorrowMorningAfterMidnightEndsToday() {
        let cal = calendar("Europe/London")
        let night = date(cal, 2026, 10, 14, 2)
        XCTAssertEqual(
            NotificationPause.make(.untilTomorrowMorning, now: night, calendar: cal).until, date(cal, 2026, 10, 14, 8)
        )
        // Exactly 08:00 is not "before" 08:00: the pause runs to the next morning.
        let eight = date(cal, 2026, 10, 14, 8)
        XCTAssertEqual(
            NotificationPause.make(.untilTomorrowMorning, now: eight, calendar: cal).until, date(cal, 2026, 10, 15, 8)
        )
    }

    func testTomorrowMorningAcrossDaylightSavingChange() {
        // Clocks go back in London on 2026-10-25: the night is 25 hours long.
        let cal = calendar("Europe/London")
        let now = date(cal, 2026, 10, 24, 23)
        XCTAssertEqual(
            NotificationPause.make(.untilTomorrowMorning, now: now, calendar: cal).until, date(cal, 2026, 10, 25, 8)
        )
    }

    func testIndefiniteAndExpired() {
        let cal = calendar("UTC")
        let now = date(cal, 2026, 10, 13, 12)
        let off = NotificationPause.make(.untilOff, now: now, calendar: cal)
        XCTAssertTrue(off.isPaused(at: now.addingTimeInterval(86400 * 365)))
        XCTAssertEqual(off.status(now: now, calendar: cal), "Paused until you turn it back on")
        XCTAssertFalse(NotificationPause().isPaused(at: now))
        XCTAssertEqual(NotificationPause(until: now.addingTimeInterval(-1)).status(now: now, calendar: cal), "Not paused")
    }

    func testAllowsHonoursMuteAndPause() throws {
        let service = try XCTUnwrap(ServiceCatalog.service(id: "discord"))
        var state = AppState()
        var tab = state.addTab(service: service)
        let now = Date()
        XCTAssertTrue(NotificationPause().allows(tab, at: now))
        XCTAssertFalse(NotificationPause(until: .distantFuture).allows(tab, at: now))
        tab.muted = true
        XCTAssertFalse(NotificationPause().allows(tab, at: now))
    }

    func testPauseSurvivesRoundTrip() throws {
        var state = AppState()
        state.settings.pause = NotificationPause(until: .distantFuture)
        state.settings.startHidden = true
        let decoded = try StateStore.decode(StateStore.encode(state))
        XCTAssertEqual(decoded.settings, state.settings)
    }
}
