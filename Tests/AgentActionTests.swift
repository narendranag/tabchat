@testable import Tabchat
import WebKit
import XCTest

/// The WhatsApp read and action scripts against an invented page. Made-up names only: this repo is public.
final class AgentActionTests: XCTestCase {
    private static let fixture = """
    <html><head><title>WhatsApp</title></head><body>
    <div id="pane-side"><div role="grid">
      <div role="row"><div data-testid="cell-frame-container"><div data-testid="cell-frame-title">
        <span title="Ada Example">Ada Example</span></div></div></div>
    </div></div>
    <div id="main">
      <header><span data-testid="conversation-info-header-chat-title">Ada Example</span></header>
      <div role="row"><div data-id="MSG1"><div class="message-in">
        <div data-pre-plain-text="[1:03 pm, 14/10/2026] Ada Example: ">
          <span data-testid="selectable-text">Here is the summary</span></div>
        <div data-testid="msg-meta">1:03 pm</div></div></div></div>
      <div role="row"><div data-id="MSG2"><div class="message-in">
        <div role="button" data-testid="document-thumb" title="View &quot;Test plan.pdf&quot;">
          <span dir="auto">Test plan.pdf</span>
          <span title="4 pages">4 pages</span><span data-testid="type" title="PDF">PDF</span><span title="10 kB">10 kB</span>
        </div>
        <div data-testid="msg-meta">1:04 pm</div></div></div></div>
      <div role="row"><div data-id="MSG3"><div class="message-out">
        <span data-testid="selectable-text">Thanks</span><div data-testid="msg-meta">1:05 pm</div></div></div></div>
    </div>
    <script>
      document.querySelector('[data-testid="document-thumb"]').addEventListener("click", () => {
        const modal = document.createElement("div");
        modal.setAttribute("data-testid", "media-viewer-modal");
        modal.innerHTML = '<button aria-label="Download"></button><div aria-label="Close"></div>';
        modal.querySelector("button").addEventListener("click", () => { document.body.dataset.downloaded = "yes"; });
        modal.querySelector("[aria-label=Close]").addEventListener("click", () => modal.remove());
        document.body.appendChild(modal);
      });
    </script>
    </body></html>
    """

    @MainActor
    private func loadFixture() async throws -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(Self.fixture, baseURL: URL(string: "https://example.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        return webView
    }

    @MainActor
    func testMessagesReader() async throws {
        let webView = try await loadFixture()
        let response = try await WhatsAppScripts.messagesResponse(json: PageReaders.run(WhatsAppScripts.messages, in: webView))
        XCTAssertEqual(response.chat, "Ada Example")
        XCTAssertEqual(response.untrusted, true)
        XCTAssertEqual(response.messages, [
            AgentMessage(
                id: "MSG1", direction: "in", sender: "Ada Example", stamp: "1:03 pm, 14/10/2026", time: "1:03 pm",
                text: "Here is the summary", document: nil
            ),
            AgentMessage(
                id: "MSG2", direction: "in", sender: "", stamp: "", time: "1:04 pm", text: "",
                document: AgentDocument(name: "Test plan.pdf", type: "PDF", details: "4 pages • PDF • 10 kB")
            ),
            AgentMessage(id: "MSG3", direction: "out", sender: "", stamp: "", time: "1:05 pm", text: "Thanks", document: nil)
        ])
    }

    @MainActor
    func testDownloadOpensViewerAndPressesDownload() async throws {
        let webView = try await loadFixture()
        let result = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.download,
            arguments: ["id": "MSG2"],
            in: webView
        ))
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.name, "Test plan.pdf")
        let pressed = try await webView.evaluateJavaScript("document.body.dataset.downloaded") as? String
        XCTAssertEqual(pressed, "yes")
        _ = try await PageReaders.run(WhatsAppScripts.closeViewer, in: webView)
        let open = try await webView
            .evaluateJavaScript("document.querySelectorAll('[data-testid=media-viewer-modal]').length") as? Int
        XCTAssertEqual(open, 0)
    }

    @MainActor
    func testDownloadRefusesMessagesWithoutADocument() async throws {
        let webView = try await loadFixture()
        let text = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.download,
            arguments: ["id": "MSG1"],
            in: webView
        ))
        XCTAssertFalse(text.ok)
        let missing = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.download,
            arguments: ["id": "NOPE"],
            in: webView
        ))
        XCTAssertEqual(missing.reason, "that message is not on screen")
    }

    @MainActor
    func testOpenRefusesAChatNotOnScreen() async throws {
        let webView = try await loadFixture()
        let result = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "Grace"],
            in: webView
        ))
        XCTAssertEqual(result.reason, "that chat is not in the chat list on screen")
    }

    func testActionsNeedTheirOwnSwitch() throws {
        var state = AppState()
        let tab = try state.addTab(service: XCTUnwrap(ServiceCatalog.service(id: "whatsapp")))
        state.settings.agentAccess = true
        state.tabs[0].agentReadable = true
        let request = AgentRequest(call: .download, tab: tab.id.uuidString)
        XCTAssertEqual(
            AgentResponder.actionTab(for: request, in: state),
            .failure(.message("actions are off for this tab (Tabchat → Settings → Agents)"))
        )
        state.tabs[0].agentActions = true
        XCTAssertEqual(try AgentResponder.actionTab(for: request, in: state).get().id, tab.id)
        XCTAssertFalse(try StateStore.decode(StateStore.encode(AppState.firstRun())).tabs[0].agentActions)
    }

    func testDownloadFolderNamesAreSafe() {
        let base = URL(fileURLWithPath: "/Users/x/Downloads")
        XCTAssertEqual(
            AgentResponder.downloadFolder(base: base, service: "whatsapp", contact: "Ada / Example: Co").path,
            "/Users/x/Downloads/Tabchat/whatsapp/Ada - Example- Co"
        )
        XCTAssertEqual(AgentResponder.folderName("../.."), "-")
        XCTAssertEqual(AgentResponder.folderName("  "), "unknown")
    }
}
