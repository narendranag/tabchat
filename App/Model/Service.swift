import Foundation

/// A kind of site Tabchat knows how to open: a built-in catalog entry or the generic custom website.
struct Service: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case builtIn
        case custom
    }

    let id: String
    let name: String
    let url: String?
    let kind: Kind
    /// Profile shared by every service of the same account family (Microsoft work). Nil = own profile.
    var defaultProfile: String?
    var defaultProfileName: String?
    /// True when the start URL depends on the user (Brightspace is per school).
    var asksForURL = false
}

enum ServiceCatalog {
    static let microsoftWork = "microsoft-work"

    static let all: [Service] = [
        Service(id: "whatsapp", name: "WhatsApp", url: "https://web.whatsapp.com", kind: .builtIn),
        Service(id: "discord", name: "Discord", url: "https://discord.com/app", kind: .builtIn),
        Service(
            id: "teams",
            name: "Teams",
            url: "https://teams.microsoft.com",
            kind: .builtIn,
            defaultProfile: microsoftWork,
            defaultProfileName: "Microsoft (work)"
        ),
        Service(
            id: "outlook-work",
            name: "Outlook (work)",
            url: "https://outlook.office.com/mail/",
            kind: .builtIn,
            defaultProfile: microsoftWork,
            defaultProfileName: "Microsoft (work)"
        ),
        Service(
            id: "outlook-personal",
            name: "Outlook (personal)",
            url: "https://outlook.live.com/mail/",
            kind: .builtIn,
            defaultProfile: "microsoft-personal",
            defaultProfileName: "Microsoft (personal)"
        ),
        Service(
            id: "onedrive",
            name: "OneDrive",
            url: "https://www.office.com/launch/onedrive",
            kind: .builtIn,
            defaultProfile: microsoftWork,
            defaultProfileName: "Microsoft (work)"
        ),
        Service(
            id: "brightspace",
            name: "Brightspace",
            url: nil,
            kind: .builtIn,
            defaultProfile: microsoftWork,
            defaultProfileName: "Microsoft (work)",
            asksForURL: true
        )
    ]

    static let custom = Service(id: "custom", name: "Website", url: nil, kind: .custom, asksForURL: true)

    static func service(id: String) -> Service? {
        all.first { $0.id == id } ?? (id == custom.id ? custom : nil)
    }
}
