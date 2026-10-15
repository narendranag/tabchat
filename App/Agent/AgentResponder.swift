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
