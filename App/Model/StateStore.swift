import Foundation

enum StateStoreError: Error, Equatable {
    case unsupportedVersion(Int)
}

/// Reads and writes `state.json`. Writes are atomic so a crash cannot leave a half-written file.
struct StateStore: Sendable {
    let fileURL: URL

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tabchat", isDirectory: true)
    }

    init(directory: URL = StateStore.defaultDirectory) {
        fileURL = directory.appendingPathComponent("state.json")
    }

    /// Nil when there is no file yet.
    func load() throws -> AppState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Self.decode(Data(contentsOf: fileURL))
    }

    func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Self.encode(state).write(to: fileURL, options: .atomic)
    }

    static func encode(_ state: AppState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> AppState {
        var state = try JSONDecoder().decode(AppState.self, from: data)
        // A newer app wrote this file; refuse rather than silently dropping fields on the next save.
        guard state.schemaVersion <= AppState.currentVersion else {
            throw StateStoreError.unsupportedVersion(state.schemaVersion)
        }
        state.schemaVersion = AppState.currentVersion
        return state
    }
}
