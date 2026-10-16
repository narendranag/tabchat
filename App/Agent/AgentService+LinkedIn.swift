import Foundation
import WebKit

/// LinkedIn Messaging (read only: chats, messages, open, history) and `profile` for LinkedIn and X.
/// Nothing here types, likes, follows, connects or sends.
extension AgentService {
    /// `chats` and `messages` on a LinkedIn tab. `chats --since` scrolls the list, so it needs the
    /// actions switch and waits while the owner uses Tabchat.
    func linkedInRead(
        _ request: AgentRequest, tab _: Tab, webView: WKWebView, state: AppState
    ) async throws -> AgentResponse {
        let now = ["nowMs": Date().timeIntervalSince1970 * 1000]
        if request.call == .messages {
            return try await LinkedInScripts.messagesResponse(json: PageReaders.run(
                LinkedInScripts.messages, arguments: now, in: webView
            ))
        }
        guard let since = request.since else {
            let json = try await PageReaders.run(LinkedInScripts.chats, arguments: now, in: webView)
            return LinkedInScripts.chatsResponse(
                json: json, countsOnly: request.countsOnly ?? false, readOnly: request.readOnly ?? false
            )
        }
        if case let .failure(error) = AgentResponder.actionTab(for: request, in: state) {
            return .failure(error.text, code: error.code)
        }
        guard !ownerActive else { return Self.ownerActiveFailure }
        guard let date = AgentResponder.isoDate(since) else { return .failure("--since takes an ISO 8601 time", code: .refused) }
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let sinceDay = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        var arguments: [String: Any] = now
        arguments["sinceDay"] = sinceDay
        let json = try await PageReaders.run(LinkedInScripts.chatsSince, arguments: arguments, in: webView)
        return LinkedInScripts.chatsResponse(
            json: json, countsOnly: request.countsOnly ?? false, readOnly: request.readOnly ?? false
        )
    }

    static var ownerActiveFailure: AgentResponse {
        .failure("the owner is using Tabchat; try again when they have been away for two minutes", code: .ownerActive)
    }

    /// `open` and `history` on a LinkedIn tab. Opening a thread may mark it read.
    func linkedInAct(_ request: AgentRequest, controller: TabController, model: AppModel) async throws -> AgentResponse {
        guard request.call == .open || request.call == .history else {
            return .failure("LinkedIn is read only here: its actions are open, history and profile", code: .refused)
        }
        guard !ownerActive else { return Self.ownerActiveFailure }
        let webView = controller.webView
        let now = Date().timeIntervalSince1970 * 1000
        if request.call == .history {
            let until = request.until ?? ""
            let screens = min(max(request.screens ?? (until.isEmpty ? 3 : 20), 1), 20)
            model.showToast("Agent reading earlier LinkedIn messages")
            let json = try await PageReaders.run(
                LinkedInScripts.history, arguments: ["screens": screens, "until": until, "nowMs": now], in: webView
            )
            var response = LinkedInScripts.messagesResponse(json: json)
            let result = LinkedInScripts.decode(json)
            if response.ok, result.partial == true {
                response.note = "stopped after 90 seconds; these are the messages read"
            } else if response.ok, result.reached == false {
                response.note = "did not reach that message within \(screens) screens; these are the messages read"
            }
            return response
        }
        guard let chat = request.chat?.trimmingCharacters(in: .whitespaces), !chat.isEmpty else {
            return .failure("open needs --chat NAME or a thread id", code: .refused)
        }
        let key = LinkedInScripts.threadId(chat)
        model.showToast("Agent opening a LinkedIn conversation")
        let result = try await LinkedInScripts.decode(PageReaders.run(LinkedInScripts.open, arguments: [
            "name": key == nil ? chat : "", "key": key ?? "", "ifRead": request.ifRead == true, "nowMs": now
        ], in: webView))
        if result.ok {
            return Self.opened(result)
        }
        // A thread id that isn't in the list: go to its address in the tab.
        guard let key, result.inList == false, let url = LinkedInScripts.threadURL(key) else {
            return LinkedInScripts.failure(result, "could not open the conversation")
        }
        guard request.ifRead != true else {
            return .failure("that thread is not in the list, so --if-read cannot check it; open it by name", code: .refused)
        }
        webView.load(URLRequest(url: url))
        let loaded = try await LinkedInScripts.decode(PageReaders.run(
            LinkedInScripts.opened, arguments: ["key": key, "nowMs": now], in: webView
        ))
        return loaded.ok ? Self.opened(loaded) : LinkedInScripts.failure(loaded, "the thread did not open")
    }

    private static func opened(_ result: LinkedInScripts.Result) -> AgentResponse {
        var response = AgentResponse(ok: true)
        response.chat = result.chat
        response.key = result.key
        response.chatProfile = result.chatProfile
        return response
    }

    /// `profile`: needs the actions switch on the LinkedIn or X tab whose sign-in it borrows; the tab
    /// itself may be asleep. One load a minute, and none while the owner uses Tabchat.
    func profile(_ request: AgentRequest, tab: Tab, model: AppModel) async -> AgentResponse {
        let target: ProfileReader.Target
        switch ProfileReader.target(request.url ?? "") {
        case let .success(found): target = found
        case let .failure(error): return .failure(error.text, code: error.code)
        }
        guard tab.serviceId == target.site else {
            let name = target.site == "x" ? "an X" : "a LinkedIn"
            return .failure("that profile needs \(name) tab (its sign-in is used)", code: .refused)
        }
        guard !ownerActive else { return Self.ownerActiveFailure }
        if let last = lastProfileLoad, Date().timeIntervalSince(last) < 60 {
            let wait = Int((60 - Date().timeIntervalSince(last)).rounded(.up))
            return .failure("one profile a minute; try again in \(wait) s", code: .rate)
        }
        lastProfileLoad = Date()
        model.showToast("Agent reading a \(target.site == "x" ? "X" : "LinkedIn") profile")
        do {
            return try await ProfileReader.read(target, dataStore: model.dataStore(for: tab))
        } catch {
            return .failure("profile failed: \(error.localizedDescription)")
        }
    }
}
