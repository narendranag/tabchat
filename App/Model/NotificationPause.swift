import Foundation

enum PauseOption: Sendable {
    case oneHour
    case untilTomorrowMorning
    case untilOff
}

/// "Do not notify me until …". Stored as an end date; "until I turn it back on" is `distantFuture`.
/// Every function takes the clock and calendar so tests can pin both.
struct NotificationPause: Codable, Equatable, Sendable {
    var until: Date?

    /// Hour of day that "until tomorrow" ends at.
    static let morningHour = 8

    static func make(_ option: PauseOption, now: Date, calendar: Calendar) -> NotificationPause {
        switch option {
        case .oneHour:
            NotificationPause(until: now.addingTimeInterval(3600))
        case .untilOff:
            NotificationPause(until: .distantFuture)
        case .untilTomorrowMorning:
            // The next 08:00 in the local time zone: tonight's pause ends tomorrow, a 02:00 one ends today.
            // Asking the calendar (not adding 24 h) keeps this right across midnight and DST changes.
            NotificationPause(until: calendar.nextDate(
                after: now, matching: DateComponents(hour: morningHour, minute: 0), matchingPolicy: .nextTime
            ))
        }
    }

    func isPaused(at now: Date) -> Bool {
        until.map { $0 > now } ?? false
    }

    /// A tab's notification is posted only when it is not muted and nothing is paused.
    func allows(_ tab: Tab, at now: Date) -> Bool {
        !tab.muted && !isPaused(at: now)
    }

    /// Whether the pause has no end other than the user's say-so.
    var isIndefinite: Bool {
        until == .distantFuture
    }

    /// "Paused until 16:30", "Paused until tomorrow 08:00", or "Not paused".
    func status(now: Date, calendar: Calendar, locale: Locale = .current) -> String {
        guard let until, isPaused(at: now) else { return "Not paused" }
        if isIndefinite {
            return "Paused until you turn it back on"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let time = formatter.string(from: until)
        if calendar.isDate(until, inSameDayAs: now) {
            return "Paused until \(time)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
            return "Paused until tomorrow \(time)"
        }
        formatter.dateStyle = .medium
        return "Paused until \(formatter.string(from: until))"
    }
}
