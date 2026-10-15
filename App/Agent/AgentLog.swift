import Foundation

/// One line per agent call: when, which process, which call, which tab, how many items, the outcome.
/// Never content. Kept 30 days in `agent.log` next to `state.json`.
struct AgentLog: Sendable {
    static let keepDays = 30

    let fileURL: URL

    init(directory: URL = StateStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("agent.log")
    }

    struct Entry: Equatable, Sendable {
        var time: Date
        var client: String
        var call: String
        var tab: String?
        var items: Int
        var error: String?
    }

    static func line(_ entry: Entry) -> String {
        let time = ISO8601DateFormatter().string(from: entry.time)
        let outcome = entry.error.map { "error: \($0)" } ?? "ok"
        return [time, entry.client, entry.call, entry.tab ?? "-", "\(entry.items) items", outcome]
            .map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\t")
    }

    /// The lines still inside the keep window; lines whose date cannot be read are dropped.
    static func trimmed(_ lines: [Substring], now: Date) -> [Substring] {
        let floor = now.addingTimeInterval(-Double(keepDays) * 86400)
        let parser = ISO8601DateFormatter()
        return lines.filter { line in
            guard let field = line.split(separator: "\t").first, let date = parser.date(from: String(field)) else {
                return false
            }
            return date >= floor
        }
    }

    func append(_ entry: Entry) {
        let data = Data((Self.line(entry) + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
            ownerOnly()
        }
    }

    /// The log names services and programs; only the owner may read it.
    private func ownerOnly() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func trim(now: Date) {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let kept = Self.trimmed(text.split(separator: "\n"), now: now)
        let output = kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n"
        try? Data(output.utf8).write(to: fileURL, options: .atomic)
        ownerOnly()
    }
}
