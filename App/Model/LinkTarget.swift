import Foundation

/// Where a link that leaves the current site opens.
enum LinkTarget: Codable, Hashable, Sendable {
    case defaultBrowser
    /// A temporary tab in the same profile as the page that held the link; not saved.
    case inTabchat
    /// An installed browser, by bundle identifier.
    case browser(String)

    private static let tabchatKey = "tabchat"

    /// Stored as one string: "default", "tabchat", or the browser's bundle id.
    init(storage: String) {
        switch storage {
        case "", "default": self = .defaultBrowser
        case Self.tabchatKey: self = .inTabchat
        default: self = .browser(storage)
        }
    }

    var storage: String {
        switch self {
        case .defaultBrowser: "default"
        case .inTabchat: Self.tabchatKey
        case let .browser(id): id
        }
    }

    init(from decoder: Decoder) throws {
        try self.init(storage: decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }
}

extension LinkPolicy {
    /// What to do with a link: the existing in/out decision, refined by the user's choice.
    enum Route: Equatable {
        /// A sign-in popup or same-site window inside the page's own web view configuration.
        case popup
        case defaultBrowser
        case browser(String)
        case temporaryTab
    }

    static func route(for target: URL, tabURLs: [URL], preference: LinkTarget) -> Route {
        if decision(for: target, tabURLs: tabURLs) == .inApp {
            return .popup
        }
        // mailto:, tel: and the like belong to the apps macOS has chosen for them, not to a browser.
        guard ["http", "https"].contains(target.scheme?.lowercased() ?? "") else { return .defaultBrowser }
        switch preference {
        case .defaultBrowser: return .defaultBrowser
        case .inTabchat: return .temporaryTab
        case let .browser(id): return .browser(id)
        }
    }
}
