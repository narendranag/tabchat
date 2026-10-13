import Foundation

enum URLInput {
    /// Turns what the user typed into a web URL, adding https:// when the scheme is missing.
    static func normalize(_ text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.contains("://") {
            s = "https://" + s
        }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host, host.contains(".") || host == "localhost"
        else { return nil }
        return url
    }
}
