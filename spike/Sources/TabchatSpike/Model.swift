import SwiftUI
import WebKit
import CryptoKit
import UserNotifications

/// One constant to change if a service rejects the user agent.
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"

let diagnosticsID = "diagnostics"
let brightspaceKey = "brightspaceURL"

struct TabSpec: Identifiable {
    let id: String
    let name: String
    let url: String?      // nil = Brightspace, asked for first
    let profile: String
}

let allTabs: [TabSpec] = [
    .init(id: "wa1", name: "WhatsApp (account 1)", url: "https://web.whatsapp.com", profile: "whatsapp-1"),
    .init(id: "wa2", name: "WhatsApp (account 2)", url: "https://web.whatsapp.com", profile: "whatsapp-2"),
    .init(id: "discord", name: "Discord", url: "https://discord.com/app", profile: "discord"),
    .init(id: "teams", name: "Teams", url: "https://teams.microsoft.com", profile: "microsoft-work"),
    .init(id: "outlook", name: "Outlook", url: "https://outlook.office.com/mail/", profile: "microsoft-work"),
    .init(id: "onedrive", name: "OneDrive", url: "https://www.office.com/launch/onedrive", profile: "microsoft-work"),
    .init(id: "brightspace", name: "Brightspace", url: nil, profile: "microsoft-work"),
    .init(id: "outlook-personal", name: "Personal Outlook", url: "https://outlook.live.com/mail/", profile: "microsoft-personal"),
]

struct LogLine: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
}

/// Name-based UUID (v5, SHA-1) so a profile name maps to the same data store on every launch.
func stableUUID(_ name: String) -> UUID {
    let ns = UUID(uuidString: "6ba7b811-9dad-11d1-80b4-00c04fd430c8")!   // the standard URL namespace
    var data = withUnsafeBytes(of: ns.uuid) { Data($0) }
    data.append(Data(("tabchat-spike/" + name).utf8))
    var h = Array(Insecure.SHA1.hash(data: data).prefix(16))
    h[6] = (h[6] & 0x0F) | 0x50
    h[8] = (h[8] & 0x3F) | 0x80
    return UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var selection: String? = "wa1"
    @Published var unread: [String: Int] = [:]
    @Published var urls: [String: String] = [:]
    @Published var log: [LogLine] = []
    @Published var brightspaceURL: String? = UserDefaults.standard.string(forKey: brightspaceKey)

    private var controllers: [String: TabController] = [:]
    private var stores: [String: WKWebsiteDataStore] = [:]

    func addLog(_ text: String) {
        log.append(LogLine(text: text))
        if log.count > 2000 { log.removeFirst(500) }
        print(text)
    }

    func store(for profile: String) -> WKWebsiteDataStore {
        if let s = stores[profile] { return s }
        let s = WKWebsiteDataStore(forIdentifier: stableUUID(profile))
        stores[profile] = s
        return s
    }

    func url(for tab: TabSpec) -> URL? {
        let s = tab.url ?? brightspaceURL
        return s.flatMap { URL(string: $0) }
    }

    /// Created on first call, then kept alive for the life of the app.
    func controller(for tab: TabSpec) -> TabController? {
        if let c = controllers[tab.id] { return c }
        guard let url = url(for: tab) else { return nil }
        let c = TabController(tab: tab, store: store(for: tab.profile), model: self)
        controllers[tab.id] = c
        c.webView.load(URLRequest(url: url))
        return c
    }

    func setBrightspace(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty && !t.contains("://") { t = "https://" + t }
        UserDefaults.standard.set(t, forKey: brightspaceKey)
        brightspaceURL = t
    }

    func setUnread(_ tab: String, _ n: Int) {
        if unread[tab] != n { unread[tab] = n }
        let total = unread.values.reduce(0, +)
        NSApp.dockTile.badgeLabel = total > 0 ? String(total) : nil
    }

    func select(_ tab: String) {
        selection = tab
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) }
    }
}
