import AppKit
import Foundation
import Observation
import WebKit

/// The agent API inside the app: keeps the notification feed, runs the socket while agents are
/// allowed, answers calls and logs each one. The read calls only read; the actions (clicks, drafts,
/// sends after the owner confirms) are in `AgentService+Actions.swift`.
@MainActor
@Observable
final class AgentService {
    @ObservationIgnored private(set) var feed = AgentFeed()
    private(set) var running = false
    private(set) var lastError: String?
    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var server: AgentSocketServer?
    /// A `send` is waiting for the owner; a second one is refused until it is answered.
    @ObservationIgnored var sendPending = false
    /// The owner's last keyboard or mouse input in Tabchat, for `status`.
    @ObservationIgnored private var lastInput: Date?
    @ObservationIgnored private var inputMonitor: Any?
    /// Asks the owner to confirm a `send`; replaced in tests.
    @ObservationIgnored var confirmSend: @MainActor (AgentSendRequest) async -> Bool = AgentSendConfirm.ask
    private let log: AgentLog
    private let socketURL: URL

    init(log: AgentLog = AgentLog(), socketURL: URL = AgentWire.socketURL) {
        self.log = log
        self.socketURL = socketURL
    }

    func attach(_ model: AppModel) {
        self.model = model
        let input: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: input) { [weak self] event in
            self?.lastInput = Date()
            return event
        }
        log.trim(now: Date())
    }

    /// Starts or stops the socket. Turning agents off also forgets the feed.
    func apply(enabled: Bool) {
        if enabled, server == nil {
            let server = AgentSocketServer(url: socketURL) { [weak self] line, peer in
                await self?.reply(to: line, client: peer) ?? Data()
            }
            do {
                try server.start()
                self.server = server
                running = true
                lastError = nil
            } catch {
                lastError = "Could not open the agent socket: \(error)"
            }
        } else if !enabled {
            server?.stop()
            server = nil
            running = false
            feed.removeAll()
        }
    }

    /// Every notification a tab posts, before pause or mute: the agent sees what arrived even when
    /// the banner was held back. Only tabs open to agents are kept.
    func record(title: String, body: String, from tab: Tab, state: AppState) {
        guard AgentResponder.readableTabs(state).contains(where: { $0.id == tab.id }) else { return }
        let now = Date()
        feed.prune(now: now)
        feed.append(AgentFeedItem(
            time: now, tab: tab.id.uuidString, service: tab.serviceId, title: title, body: body,
            chat: tab.serviceId == "whatsapp" && !title.isEmpty ? title : nil
        ))
    }

    private func reply(to line: Data, client: String) async -> Data {
        let response: AgentResponse
        var request: AgentRequest?
        do {
            let decoded = try AgentWire.decoder().decode(AgentRequest.self, from: line)
            request = decoded
            response = await answer(decoded, client: client)
        } catch {
            response = .failure("bad request: expected one JSON object such as {\"call\":\"tabs\"}")
        }
        log.append(AgentLog.Entry(
            time: Date(), client: client, call: request?.call.rawValue ?? "invalid",
            tab: request?.tab.flatMap { id in model?.tabs.first { $0.id.uuidString == id }?.displayName } ?? request?.tab,
            items: Self.itemCount(response), error: response.error
        ))
        return (try? AgentWire.line(response)) ?? Data("{\"ok\":false}\n".utf8)
    }

    func answer(_ request: AgentRequest, client: String = "An agent") async -> AgentResponse {
        guard let model else { return .failure("Tabchat is starting") }
        let state = model.state
        guard state.settings.agentAccess else { return .failure("agent access is off in Tabchat's settings") }
        switch request.call {
        case .tabs:
            let loaded = Set(model.controllers.keys).subtracting(model.sleeping)
            return AgentResponder.tabs(state: state, unread: model.unread, loaded: loaded)
        case .feed:
            return AgentResponder.feed(request: request, state: state, feed: feed, now: Date())
        case .status:
            return status(model: model, state: state)
        case .chats, .page, .inspect, .messages:
            return await read(request, model: model, state: state)
        case .open, .download, .contact, .history, .draft, .send:
            return await act(request, model: model, state: state, client: client)
        }
    }

    private func read(_ request: AgentRequest, model: AppModel, state: AppState) async -> AgentResponse {
        let tab: Tab
        switch AgentResponder.tab(for: request, in: state) {
        case let .success(found): tab = found
        case let .failure(error): return .failure(error.text)
        }
        guard let webView = model.controllers[tab.id]?.webView, !model.sleeping.contains(tab.id) else {
            return .failure("the tab is asleep or not loaded; select it in Tabchat first")
        }
        do {
            if request.call == .inspect {
                #if DEBUG
                    let dom = try await PageReaders.run(
                        PageReaders.inspect,
                        arguments: ["selector": request.selector ?? "body", "maxDepth": 30], in: webView
                    )
                    return AgentResponse(ok: true, untrusted: true, dom: dom)
                #else
                    return .failure("inspect is only in debug builds")
                #endif
            }
            if request.call == .messages {
                guard tab.serviceId == "whatsapp" else { return .failure("no message reader for \(tab.serviceId) yet; use page") }
                return try await WhatsAppScripts.messagesResponse(json: PageReaders.run(WhatsAppScripts.messages, in: webView))
            }
            if request.call == .page {
                let json = try await PageReaders.run(
                    PageReaders.pageText, arguments: ["max": AgentWire.maxPageCharacters], in: webView
                )
                return PageReaders.pageResponse(json: json)
            }
            if let since = request.since {
                return try await chatsSince(since, request: request, tab: tab, webView: webView, state: state)
            }
            guard let script = PageReaders.chatList(serviceId: tab.serviceId) else {
                return .failure("no chat-list reader for \(tab.serviceId) yet; use page")
            }
            let json = try await PageReaders.run(script, in: webView)
            return PageReaders.chatsResponse(
                json: json, countsOnly: request.countsOnly ?? false, readOnly: request.readOnly ?? false
            )
        } catch {
            return .failure("reader failed: \(error.localizedDescription)")
        }
    }

    private func status(model: AppModel, state: AppState) -> AgentResponse {
        let readable = AgentResponder.readableTabs(state)
        let selected = readable.first { $0.id == state.selectedTabId }?.id.uuidString
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let window = MainWindow.shared.window
        var response = AgentResponse(ok: true, status: AgentStatus(
            focused: NSApp.isActive && window?.isKeyWindow == true,
            tabchatInputSecondsAgo: lastInput.map { Date().timeIntervalSince($0) },
            macIdleSeconds: idle, selectedTab: selected, sendPending: sendPending
        ))
        response.tabs = AgentResponder.tabs(
            state: state, unread: model.unread, loaded: Set(model.controllers.keys).subtracting(model.sleeping)
        ).tabs
        return response
    }

    /// `chats --since`: scrolls the chat list, so it needs the tab's actions switch as well.
    private func chatsSince(
        _ since: String, request: AgentRequest, tab: Tab, webView: WKWebView, state: AppState
    ) async throws -> AgentResponse {
        guard tab.serviceId == "whatsapp" else { return .failure("chats --since is WhatsApp only so far") }
        if case let .failure(error) = AgentResponder.actionTab(for: request, in: state) {
            return .failure(error.text)
        }
        guard let date = AgentResponder.isoDate(since) else { return .failure("--since takes an ISO 8601 time") }
        let midnight = Calendar.current.startOfDay(for: date)
        let order = DateFormatter.dateFormat(fromTemplate: "ddMMyyyy", options: 0, locale: .current) ?? "dd"
        let json = try await PageReaders.run(PageReaders.whatsAppChatListSince, arguments: [
            "sinceMs": midnight.timeIntervalSince1970 * 1000, "dayFirst": order.hasPrefix("d")
        ], in: webView)
        return PageReaders.chatsResponse(json: json, countsOnly: request.countsOnly ?? false, readOnly: request.readOnly ?? false)
    }

    private static func itemCount(_ response: AgentResponse) -> Int {
        response.tabs?.count ?? response.feed?.count ?? response.chats?.count ?? response.counts?.chats
            ?? response.messages?
            .count ?? ([response.page != nil, response.file != nil, response.contact != nil].contains(true) ? 1 : 0)
    }
}
