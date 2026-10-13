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

/// Files from before schema 2 have no `muted` key.
extension Tab {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        serviceId = try values.decode(String.self, forKey: .serviceId)
        profileId = try values.decode(String.self, forKey: .profileId)
        customName = try values.decodeIfPresent(String.self, forKey: .customName)
        customURL = try values.decodeIfPresent(String.self, forKey: .customURL)
        colorHex = try values.decode(String.self, forKey: .colorHex)
        muted = try values.decodeIfPresent(Bool.self, forKey: .muted) ?? false
    }
}
