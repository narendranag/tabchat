import Foundation

struct Tab: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var serviceId: String
    var profileId: String
    var customName: String?
    var customURL: String?
    var colorHex: String

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
