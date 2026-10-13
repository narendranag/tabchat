import AppKit

/// Site icons fetched once from the page itself and cached in Application Support. No third-party
/// logos ship with the app.
@MainActor
final class IconStore {
    private let directory: URL

    init(directory: URL = StateStore.defaultDirectory.appendingPathComponent("icons", isDirectory: true)) {
        self.directory = directory
    }

    func cached(key: String) -> NSImage? {
        NSImage(contentsOf: fileURL(key))
    }

    /// Tries each candidate in order and keeps the first that decodes as an image.
    func fetch(candidates: [URL], key: String) async -> NSImage? {
        for url in candidates {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.size.width >= 16
            else { continue }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: fileURL(key), options: .atomic)
            return image
        }
        return nil
    }

    private func fileURL(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".icon")
    }
}
