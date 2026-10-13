import Foundation

/// Things the Cmd+K palette can do besides switching tabs.
enum PaletteAction: String, CaseIterable, Sendable {
    case newService
    case reload
    case find
    case toggleSplit
    case pauseOneHour
    case pauseUntilTomorrow
    case resume
    case settings
    case duplicateTab
    case sleepTab

    var title: String {
        switch self {
        case .newService: "New Service…"
        case .reload: "Reload"
        case .find: "Find on Page"
        case .toggleSplit: "Toggle Split View"
        case .pauseOneHour: "Pause Notifications for 1 Hour"
        case .pauseUntilTomorrow: "Pause Notifications Until Tomorrow"
        case .resume: "Resume Notifications"
        case .settings: "Settings…"
        case .duplicateTab: "Duplicate Tab"
        case .sleepTab: "Sleep Tab"
        }
    }
}

struct PaletteItem: Identifiable, Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case tab(UUID)
        case action(PaletteAction)
    }

    let target: Target
    let title: String
    let unread: Int
    let sleeping: Bool

    var id: String {
        switch target {
        case let .tab(id): "tab-\(id.uuidString)"
        case let .action(action): "action-\(action.rawValue)"
        }
    }

    static func tab(_ id: UUID, title: String, unread: Int = 0, sleeping: Bool = false) -> PaletteItem {
        PaletteItem(target: .tab(id), title: title, unread: unread, sleeping: sleeping)
    }

    static func action(_ action: PaletteAction) -> PaletteItem {
        PaletteItem(target: .action(action), title: action.title, unread: 0, sleeping: false)
    }
}

/// Filters and orders palette items for a query. Case-insensitive; a match is, best first, a title
/// that starts with the query, a word that starts with it, any substring, or the query's letters
/// in order (so "wa" finds WhatsApp and "tgs" finds Toggle Split). Ties keep the incoming order,
/// which lists tabs before actions.
enum PaletteRanker {
    static func score(_ query: String, in title: String) -> Int? {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        let hay = title.lowercased()
        guard !needle.isEmpty else { return 0 }
        if hay.hasPrefix(needle) {
            return 400 - hay.count
        }
        if hay.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(needle) }) {
            return 300 - hay.count
        }
        if hay.contains(needle) {
            return 200 - hay.count
        }
        var rest = hay[...]
        for char in needle {
            guard let found = rest.firstIndex(of: char) else { return nil }
            rest = rest[rest.index(after: found)...]
        }
        return 100 - hay.count
    }

    static func rank(_ items: [PaletteItem], query: String) -> [PaletteItem] {
        let scored = items.enumerated().compactMap { index, item in
            score(query, in: item.title).map { (index, $0, item) }
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.map(\.2)
    }

    /// Arrow-key movement through `count` results; stops at the ends.
    static func move(_ index: Int, by delta: Int, count: Int) -> Int {
        count == 0 ? 0 : min(max(index + delta, 0), count - 1)
    }
}
