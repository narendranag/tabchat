import Foundation

enum DownloadNaming {
    /// First free file name in `directory`: "report.pdf", then "report 1.pdf", "report 2.pdf", ...
    static func uniqueURL(in directory: URL, filename: String, exists: (URL) -> Bool) -> URL {
        let safe = (filename as NSString).lastPathComponent
        let name = safe.isEmpty ? "download" : safe
        var candidate = directory.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 1
        while exists(candidate) {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }
}
