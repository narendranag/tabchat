import Foundation

/// Decides whether a link that wants a new window stays in the app or goes to the default browser.
enum LinkPolicy {
    enum Decision {
        case inApp
        case external
    }

    /// Sign-in pages must stay in-app, or the session cookie lands in the wrong place.
    private static let signInHosts: [(host: String, pathPrefix: String?)] = [
        ("login.microsoftonline.com", nil),
        ("login.microsoft.com", nil),
        ("login.live.com", nil),
        ("accounts.google.com", nil),
        ("appleid.apple.com", nil),
        ("discord.com", "/oauth2")
    ]

    /// Domains that belong to one product, so a Teams link to office.com is not "another site".
    private static let siteGroups: [[String]] = [
        [
            "microsoft.com",
            "office.com",
            "live.com",
            "microsoftonline.com",
            "sharepoint.com",
            "office365.com",
            "microsoft365.com",
            "office.net",
            "skype.com"
        ],
        ["discord.com", "discordapp.com", "discord.gg"],
        ["whatsapp.com", "whatsapp.net"],
        ["x.com", "twitter.com", "t.co", "twimg.com"],
        ["reddit.com", "redd.it", "redditmedia.com", "redditstatic.com"]
    ]

    private static let secondLevelLabels: Set<String> = ["co", "com", "org", "net", "gov", "ac", "edu"]

    static func decision(for target: URL, tabURLs: [URL]) -> Decision {
        let scheme = target.scheme?.lowercased() ?? ""
        if ["about", "blob", "data", "javascript"].contains(scheme) {
            return .inApp
        }
        guard scheme == "http" || scheme == "https" else { return .external }
        guard let host = target.host?.lowercased() else { return .inApp }
        if isSignIn(host: host, path: target.path) {
            return .inApp
        }
        let key = siteKey(host: host)
        return tabURLs.contains { $0.host.map { siteKey(host: $0.lowercased()) } == key } ? .inApp : .external
    }

    static func isSignIn(host: String, path: String) -> Bool {
        signInHosts.contains { entry in
            host == entry.host && (entry.pathPrefix.map { path.hasPrefix($0) } ?? true)
        }
    }

    /// A stable identity for "the same site": the product group, else the registrable domain.
    static func siteKey(host: String) -> String {
        for group in siteGroups where group.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return group[0]
        }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        let takesThree = labels[labels.count - 1].count == 2 && secondLevelLabels.contains(labels[labels.count - 2])
        return labels.suffix(takesThree ? 3 : 2).joined(separator: ".")
    }
}
