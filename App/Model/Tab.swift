import Foundation

struct Tab: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var serviceId: String
    var profileId: String
    var customName: String?
    var customURL: String?
    var colorHex: String
    /// Muted tabs never post notifications (their unread count still shows).
    var muted = false
    /// Whether the idle timer may release this tab's web view (off for chat tabs, so notifications keep working).
    var allowSleep = true
    /// Where a sleeping tab was when it slept (or a duplicate was made); the next load starts there.
    var lastURL: String?
    /// Local agents may read this tab while agent access is on. Off by default; never for incognito tabs.
    var agentReadable = false
    /// Agents may also act in this tab: open chats, read contact info, download attachments, write drafts, and
    /// send a message once the owner confirms it in Tabchat.
    var agentActions = false
    /// Incognito and temporary tabs live for this run only: they are never written to `state.json`.
    var incognito = false
    var temporary = false

    var isEphemeral: Bool {
        incognito || temporary
    }

    var service: Service {
        ServiceCatalog.service(id: serviceId) ?? ServiceCatalog.custom
    }

    var displayName: String {
        customName ?? service.name
    }

    var startURL: URL? {
        (customURL ?? service.url).flatMap(URLInput.normalize)
    }

    /// Key for the cached icon: all accounts of one site share one icon.
    var iconKey: String {
        startURL?.host?.lowercased() ?? id.uuidString
    }
}

enum TabPalette {
    static let colors = ["2F80ED", "27AE60", "E2574C", "F2994A", "9B51E0", "00A3A3", "D6336C", "5C7CFA"]
}

/// Files from before schema 2 have no `muted` key, and before schema 3 no `allowSleep` or `lastURL`.
/// `incognito` and `temporary` are deliberately not coded.
extension Tab {
    enum CodingKeys: String, CodingKey {
        case id, serviceId, profileId, customName, customURL, colorHex, muted, allowSleep, lastURL, agentReadable, agentActions
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serviceId = try values.decode(String.self, forKey: .serviceId)
        profileId = try values.decode(String.self, forKey: .profileId)
        customName = try values.decodeIfPresent(String.self, forKey: .customName)
        customURL = try values.decodeIfPresent(String.self, forKey: .customURL)
        colorHex = try values.decode(String.self, forKey: .colorHex)
        muted = try values.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        allowSleep = try values.decodeIfPresent(Bool.self, forKey: .allowSleep)
            ?? ServiceCatalog.allowsSleepByDefault(serviceId: serviceId)
        lastURL = try values.decodeIfPresent(String.self, forKey: .lastURL)
        agentReadable = try values.decodeIfPresent(Bool.self, forKey: .agentReadable) ?? false
        agentActions = try values.decodeIfPresent(Bool.self, forKey: .agentActions) ?? false
    }
}
