import Foundation

/// A `<link rel="icon">` found in a page, as reported by the injected JS.
struct IconCandidate: Codable, Equatable, Sendable {
    let href: String
    let apple: Bool
    let size: Int

    /// Best first: apple-touch-icons (large PNGs), then the largest declared icon, then /favicon.ico.
    static func ranked(_ found: [IconCandidate], pageURL: URL) -> [URL] {
        let sorted = found.sorted { a, b in
            a.apple != b.apple ? a.apple : a.size > b.size
        }
        var urls = sorted.compactMap { URL(string: $0.href, relativeTo: pageURL)?.absoluteURL }
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL {
            urls.append(fallback)
        }
        var seen = Set<URL>()
        return urls.filter { seen.insert($0).inserted }
    }
}
