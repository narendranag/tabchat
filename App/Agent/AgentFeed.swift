import Foundation

/// Notifications kept for agents: in memory only, never written to disk, bounded by count and age,
/// so Tabchat does not become a second copy of everyone's messages.
struct AgentFeed: Sendable {
    static let capacity = 500
    static let maxAge: TimeInterval = 24 * 60 * 60

    private(set) var items: [AgentFeedItem] = []

    mutating func append(_ item: AgentFeedItem) {
        items.append(item)
        if items.count > Self.capacity {
            items.removeFirst(items.count - Self.capacity)
        }
    }

    /// Items for the given tabs, newer than `since` and younger than `maxAge`, oldest first.
    func items(tabs: Set<String>, since: Date?, now: Date) -> [AgentFeedItem] {
        let floor = max(since ?? .distantPast, now.addingTimeInterval(-Self.maxAge))
        return items.filter { tabs.contains($0.tab) && $0.time > floor }
    }

    mutating func prune(now: Date) {
        let floor = now.addingTimeInterval(-Self.maxAge)
        items.removeAll { $0.time <= floor }
    }

    mutating func removeAll() {
        items.removeAll()
    }
}
