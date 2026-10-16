import Foundation
import WebKit

/// `get` on a ManageBac tab: read tier, never an action. See `ManageBac` for the limits.
extension AgentService {
    private struct ManageBacTarget {
        var controller: TabController
        var origin: URL
        var path: String
    }

    /// The readable ManageBac tab, its site (only while it shows ManageBac) and the path asked for.
    private func manageBacTarget(
        _ request: AgentRequest, model: AppModel, state: AppState
    ) -> Result<ManageBacTarget, AgentError> {
        let tab: Tab
        switch AgentResponder.tab(for: request, in: state) {
        case let .success(found): tab = found
        case let .failure(error): return .failure(error)
        }
        guard tab.serviceId == "managebac" else { return .failure(.coded("get is for ManageBac tabs only", .refused)) }
        guard let controller = model.controllers[tab.id], !model.sleeping.contains(tab.id) else {
            return .failure(.coded("the tab is asleep or not loaded; select it in Tabchat first", .asleep))
        }
        guard let page = controller.webView.url, ManageBac.isManageBac(page),
              let origin = URL(string: "https://\(page.host ?? "")")
        else { return .failure(.coded("the tab is not on a ManageBac site (https://<school>.managebac.com)", .refused)) }
        return ManageBac.path(request.path ?? "", origin: origin, save: request.save == true)
            .map { ManageBacTarget(controller: controller, origin: origin, path: $0) }
    }

    func manageBac(_ request: AgentRequest, model: AppModel, state: AppState) async -> AgentResponse {
        let target: ManageBacTarget
        switch manageBacTarget(request, model: model, state: state) {
        case let .success(found): target = found
        case let .failure(error): return .failure(error.text, code: error.code)
        }
        let (controller, origin, path, save) = (target.controller, target.origin, target.path, request.save == true)
        if let refusal = manageBacGate.refusal(now: Date()) {
            return refusal
        }
        manageBacGate.busy = true
        defer { manageBacGate.busy = false }
        let pause = manageBacGate.wait(now: Date(), jitter: Double.random(in: 0 ... 1))
        if pause > 0 {
            try? await Task.sleep(for: .seconds(pause))
        }
        manageBacGate.record(now: Date())
        let response: AgentResponse
        let problem: (AgentErrorCode, String)?
        if save {
            (response, problem) = await manageBacSave(path: path, origin: origin, controller: controller)
        } else {
            do {
                let json = try await PageReaders.run(ManageBac.get, arguments: [
                    "path": path, "maxText": ManageBac.maxText, "maxHTML": ManageBac.maxHTML
                ], in: controller.webView)
                (response, problem) = ManageBac.response(json: json, origin: origin)
            } catch {
                // A network error inside the page: stop too, rather than try again.
                (response, problem) = (
                    .failure("network: \(error.localizedDescription); stopped for an hour", code: .checkpoint),
                    (.checkpoint, "network: the request failed")
                )
            }
        }
        if let problem {
            manageBacGate.stop(problem.0, problem.1, now: Date())
            model.showToast("ManageBac reader stopped: \(problem.1)")
        }
        return response
    }

    /// One attachment, fetched by the tab's own download machinery with its cookies. Redirects to
    /// storage on other hosts are followed (a GET); web pages and files over 25 MB are refused.
    private func manageBacSave(
        path: String, origin: URL, controller: TabController
    ) async -> (AgentResponse, (AgentErrorCode, String)?) {
        guard controller.agentDownload == nil, let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            return (.failure("another agent download is running", code: .busy), nil)
        }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tabchat/managebac", isDirectory: true)
        let slot = AgentDownloadSlot(directory: folder)
        var problem: (AgentErrorCode, String)?
        var type = ""
        slot.check = { response in
            type = response.mimeType ?? ""
            let found = ManageBac.fileRefusal(
                status: (response as? HTTPURLResponse)?.statusCode ?? 200, mimeType: type, url: response.url,
                expectedLength: response.expectedContentLength, origin: origin
            )
            problem = found?.stop
            return found?.reason
        }
        controller.agentDownload = slot
        defer { controller.agentDownload = nil }
        let download = await controller.webView.startDownload(using: URLRequest(url: url))
        download.delegate = controller
        for _ in 0 ..< 1200 where slot.finished == nil && slot.failure == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let problem {
            return (.failure(problem.1, code: problem.0), problem)
        }
        if let failure = slot.failure {
            return (.failure("not saved: \(failure)"), nil)
        }
        guard let saved = slot.finished else {
            _ = await download.cancel()
            return (.failure("the download did not finish within two minutes"), nil)
        }
        let bytes = (try? saved.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if Int64(bytes) > ManageBac.maxFileBytes {
            try? FileManager.default.removeItem(at: saved)
            return (.failure("the file was larger than 25 MB; deleted"), nil)
        }
        var response = AgentResponse(ok: true, file: AgentFile(
            path: saved.path, bytes: bytes, name: saved.lastPathComponent, contentType: type
        ))
        response.untrusted = true
        return (response, nil)
    }
}
