import Foundation

/// "Sleep after": minutes a tab may sit unselected before its web view is released. 0 = never.
enum SleepAfter {
    static let options = [0, 15, 30, 60]
    static let standard = 30

    static func label(_ minutes: Int) -> String {
        minutes == 0 ? "Never" : "\(minutes) minutes"
    }
}

/// Remembers when each tab was last on screen and decides which are due to sleep. It never reads
/// the system clock; callers pass `now`, so tests can move time by hand.
struct SleepClock: Equatable, Sendable {
    private(set) var lastShown: [UUID: Date] = [:]

    /// Marks tabs as on screen right now.
    mutating func touch(_ ids: some Sequence<UUID>, at now: Date) {
        for id in ids {
            lastShown[id] = now
        }
    }

    /// A tab seen for the first time starts its idle time now.
    mutating func track(_ ids: some Sequence<UUID>, at now: Date) {
        for id in ids where lastShown[id] == nil {
            lastShown[id] = now
        }
    }

    mutating func forget(_ id: UUID) {
        lastShown[id] = nil
    }

    /// Tabs to release: awake, allowed to sleep, not on screen, and idle for `afterMinutes` or more.
    /// Incognito and temporary tabs never sleep: they cannot be recreated.
    func due(tabs: [Tab], awake: (UUID) -> Bool, visible: Set<UUID>, afterMinutes: Int, now: Date) -> [UUID] {
        guard afterMinutes > 0 else { return [] }
        return tabs.compactMap { tab in
            guard tab.allowSleep, !tab.isEphemeral, awake(tab.id), !visible.contains(tab.id),
                  let shown = lastShown[tab.id],
                  now.timeIntervalSince(shown) >= Double(afterMinutes) * 60
            else { return nil }
            return tab.id
        }
    }
}
