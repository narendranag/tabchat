import Foundation
import WebKit

/// The actions tier: open a chat, download a file, read contact details, write a draft, and send a
/// message once the owner confirms it in Tabchat. Only for tabs whose "actions" switch is on, and
/// only WhatsApp for now.
extension AgentService {
    func act(_ request: AgentRequest, model: AppModel, state: AppState, client: String) async -> AgentResponse {
        let tab: Tab
        switch AgentResponder.actionTab(for: request, in: state) {
        case let .success(found): tab = found
        case let .failure(error): return .failure(error.text)
        }
        guard tab.serviceId == "whatsapp" else { return .failure("actions exist only for WhatsApp so far") }
        guard let controller = model.controllers[tab.id], !model.sleeping.contains(tab.id) else {
            return .failure("the tab is asleep or not loaded; select it in Tabchat first")
        }
        do {
            switch request.call {
            case .open:
                return try await open(request, controller: controller, model: model)
            case .download:
                return try await download(request, tab: tab, controller: controller, model: model)
            case .contact, .history:
                return try await read(request, controller: controller, model: model)
            case .draft, .send:
                return try await compose(request, tab: tab, controller: controller, model: model, client: client)
            default:
                return .failure("not an action")
            }
        } catch {
            return .failure("action failed: \(error.localizedDescription)")
        }
    }

    /// `draft` types the message and leaves it for the owner; `send` asks the owner first, in Tabchat's
    /// own dialog, and only then types and sends it. One message, one chat, one confirmation per call.
    private func compose(
        _ request: AgentRequest, tab: Tab, controller: TabController, model: AppModel, client: String
    ) async throws -> AgentResponse {
        // Refused before anything else, so a second send cannot switch chats under an open dialog.
        let send = request.call == .send
        if send {
            guard !sendPending else { return .failure("another message is waiting for confirmation in Tabchat") }
            sendPending = true
        }
        defer {
            if send {
                sendPending = false
            }
        }
        let text: String, chat: String
        switch try await composeTarget(request, controller: controller, model: model) {
        case let .success(target): (text, chat) = target
        case let .failure(error): return .failure(error.text)
        }
        if send {
            model.reveal(tab.id)
            guard await confirmSend(chat, text, client) else {
                return .failure("not sent: the message was cancelled in Tabchat")
            }
        }
        let result = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.compose, arguments: ["chat": chat, "text": text, "send": send], in: controller.webView
        ))
        guard result.ok else { return .failure(result.reason ?? "could not write the message") }
        if !send {
            model.reveal(tab.id)
        }
        model.showToast(send ? "Sent to \(chat)" : "Draft from \(client) in \(chat): read it, then press Return to send")
        var response = AgentResponse(ok: true)
        response.chat = chat
        return response
    }

    /// The message and the chat it goes to: `chat` opened if given, else the chat already open.
    private func composeTarget(
        _ request: AgentRequest, controller: TabController, model: AppModel
    ) async throws -> Result<(String, String), AgentError> {
        let text: String
        switch AgentResponder.messageText(request) {
        case let .success(found): text = found
        case let .failure(error): return .failure(error)
        }
        if let name = request.chat, !name.isEmpty {
            let opened = try await open(request, controller: controller, model: model)
            guard opened.ok else { return .failure(.message(opened.error ?? "could not open the chat")) }
        }
        let chat = try await WhatsAppScripts.decode(PageReaders.run(WhatsAppScripts.messages, in: controller.webView)).chat ?? ""
        return chat.isEmpty ? .failure(.message("no chat open; pass --chat NAME")) : .success((text, chat))
    }

    /// The actions that only open panels or scroll: `contact` and `history`.
    private func read(_ request: AgentRequest, controller: TabController, model: AppModel) async throws -> AgentResponse {
        if request.call == .history {
            let screens = min(max(request.screens ?? 3, 1), 20)
            model.showToast("Agent reading earlier messages")
            return try await WhatsAppScripts.messagesResponse(json: PageReaders.run(
                WhatsAppScripts.history, arguments: ["screens": screens], in: controller.webView
            ))
        }
        model.showToast("Agent reading contact info")
        let result = try await WhatsAppScripts.decode(PageReaders.run(WhatsAppScripts.contact, in: controller.webView))
        guard result.ok, let contact = result.contact else { return .failure(result.reason ?? "no contact details") }
        return AgentResponse(ok: true, untrusted: true, contact: contact)
    }

    private func open(_ request: AgentRequest, controller: TabController, model: AppModel) async throws -> AgentResponse {
        guard let name = request.chat, !name.isEmpty else { return .failure("open needs --chat NAME") }
        model.showToast("Agent opening \(name)")
        let result = try await WhatsAppScripts.decode(
            PageReaders.run(WhatsAppScripts.open, arguments: ["name": name], in: controller.webView)
        )
        guard result.ok else { return .failure(result.reason ?? "could not open the chat") }
        var response = AgentResponse(ok: true)
        response.chat = name
        return response
    }

    private func download(
        _ request: AgentRequest, tab: Tab, controller: TabController, model: AppModel
    ) async throws -> AgentResponse {
        guard let id = request.message, !id.isEmpty else { return .failure("download needs --message ID") }
        guard controller.agentDownload == nil else { return .failure("another agent download is running") }
        let chat = try await WhatsAppScripts.decode(PageReaders.run(WhatsAppScripts.messages, in: controller.webView)).chat ?? ""
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let slot = AgentDownloadSlot(directory: AgentResponder.downloadFolder(base: base, service: tab.serviceId, contact: chat))
        controller.agentDownload = slot
        defer { controller.agentDownload = nil }
        model.showToast("Agent downloading from \(chat)")
        let started = try await WhatsAppScripts.decode(
            PageReaders.run(WhatsAppScripts.download, arguments: ["id": id], in: controller.webView)
        )
        guard started.ok else { return .failure(started.reason ?? "could not start the download") }
        // Up to a minute for the file; WhatsApp fetches and decrypts it first.
        for _ in 0 ..< 600 where slot.finished == nil && slot.failure == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        _ = try? await PageReaders.run(WhatsAppScripts.closeViewer, in: controller.webView)
        if let failure = slot.failure {
            return .failure("download failed: \(failure)")
        }
        guard let url = slot.finished else { return .failure("the download did not start within a minute") }
        if let expected = started.name, !AgentResponder.sameFile(expected, saved: url.lastPathComponent) {
            return .failure("saved \(url.path), which is not the expected \(expected); check it and try again")
        }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var response = AgentResponse(ok: true, file: AgentFile(path: url.path, bytes: bytes))
        response.chat = chat
        return response
    }
}
