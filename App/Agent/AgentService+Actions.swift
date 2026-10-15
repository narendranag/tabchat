import Foundation
import WebKit

/// The actions tier: open a chat, download a document, read contact details. Only for tabs whose
/// "actions" switch is on, only WhatsApp for now, and never anything that sends.
extension AgentService {
    func act(_ request: AgentRequest, model: AppModel, state: AppState) async -> AgentResponse {
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
            case .contact:
                return .failure("contact is not built yet")
            default:
                return .failure("not an action")
            }
        } catch {
            return .failure("action failed: \(error.localizedDescription)")
        }
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
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var response = AgentResponse(ok: true, file: AgentFile(path: url.path, bytes: bytes))
        response.chat = chat
        return response
    }
}
