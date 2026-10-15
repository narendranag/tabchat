import Foundation

/// The parts of answering an agent that need no web view: who may read what, `tabs` and `feed`.
enum AgentResponder {
    /// Tabs an agent may read: the agent switch is on, the tab is ticked, and it is not incognito.
    static func readableTabs(_ state: AppState) -> [Tab] {
        guard state.settings.agentAccess else { return [] }
        return state.tabs.filter { $0.agentReadable && !$0.incognito }
    }

    /// The readable tab a request names, or the error to answer with.
    static func tab(for request: AgentRequest, in state: AppState) -> Result<Tab, AgentError> {
        guard let id = request.tab else { return .failure(.message("this call needs a tab id")) }
        guard let tab = readableTabs(state).first(where: { $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame })
        else { return .failure(.message("no readable tab with that id")) }
        return .success(tab)
    }

    /// The tab a request names when actions are allowed there too.
    static func actionTab(for request: AgentRequest, in state: AppState) -> Result<Tab, AgentError> {
        switch tab(for: request, in: state) {
        case let .success(tab) where tab.agentActions: .success(tab)
        case .success: .failure(.message("actions are off for this tab (Tabchat → Settings → Agents)"))
        case let .failure(error): .failure(error)
        }
    }

    /// `~/Downloads/Tabchat/<service>/<contact>/`, with the names made safe for a folder.
    static func downloadFolder(base: URL, service: String, contact: String) -> URL {
        base.appendingPathComponent("Tabchat", isDirectory: true)
            .appendingPathComponent(folderName(service), isDirectory: true)
            .appendingPathComponent(folderName(contact), isDirectory: true)
    }

    /// Whether a saved file is the document expected: the same name, perhaps with the " 1" the
    /// download folder adds to keep an earlier copy. An empty expected name (photos) always matches.
    static func sameFile(_ expected: String, saved: String) -> Bool {
        guard !expected.isEmpty else { return true }
        let want = (expected as NSString).deletingPathExtension.lowercased()
        var got = (saved as NSString).deletingPathExtension.lowercased()
        if let range = got.range(of: #" \d+$"#, options: .regularExpression), got != want {
            got.removeSubrange(range)
        }
        return got == want && (expected as NSString).pathExtension.lowercased() == (saved as NSString).pathExtension.lowercased()
    }

    static func folderName(_ raw: String) -> String {
        let cleaned = raw.map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return name.isEmpty ? "unknown" : String(name.prefix(80))
    }

    static func tabs(state: AppState, unread: [UUID: Unread], loaded: Set<UUID>) -> AgentResponse {
        let tabs = readableTabs(state).map { tab in
            let value = unread[tab.id] ?? .none
            return AgentTabInfo(
                id: tab.id.uuidString, name: tab.displayName, service: tab.serviceId,
                unread: value.count, unreadDot: value.dot && value.count < 1, loaded: loaded.contains(tab.id)
            )
        }
        return AgentResponse(ok: true, tabs: tabs)
    }

    static func feed(request: AgentRequest, state: AppState, feed: AgentFeed, now: Date) -> AgentResponse {
        var ids = Set(readableTabs(state).map(\.id.uuidString))
        if request.tab != nil {
            switch tab(for: request, in: state) {
            case let .success(tab): ids = [tab.id.uuidString]
            case let .failure(error): return .failure(error.text)
            }
        }
        let since = request.sinceSeconds.map { now.addingTimeInterval(-$0) }
        let items = feed.items(tabs: ids, since: since, now: now)
        return AgentResponse(ok: true, untrusted: items.isEmpty ? nil : true, feed: items)
    }
}

enum AgentError: Error, Equatable {
    case message(String)

    var text: String {
        switch self {
        case let .message(text): text
        }
    }
}
