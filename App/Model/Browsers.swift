import AppKit

/// An installed web browser the user can send links to.
struct BrowserApp: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}

enum Browsers {
    private static let ownBundleId = Bundle.main.bundleIdentifier

    /// Every app that can open an https link, other than Tabchat itself, sorted by name.
    static func installed() -> [BrowserApp] {
        let sample = URL(string: "https://example.com")!
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: sample).compactMap { url in
            guard let id = Bundle(url: url)?.bundleIdentifier, id != ownBundleId, seen.insert(id).inserted else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return BrowserApp(id: id, name: name, url: url)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Opens `url` in the browser with this bundle id; false when it is no longer installed.
    @MainActor
    static func open(_ url: URL, bundleId: String) -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return false }
        Task {
            _ = try? await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        return true
    }
}
