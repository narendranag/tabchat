@testable import Tabchat
import WebKit
import XCTest

/// The WhatsApp read and action scripts against an invented page. Made-up names only: this repo is public.
final class AgentActionTests: XCTestCase {
    private static let fixture = """
    <html><head><title>WhatsApp</title></head><body>
    <div id="side"><div data-testid="chat-list-search-container"><input type="text" value=""></div></div>
    <div id="pane-side"><div role="grid">
      <div role="row"><div data-testid="cell-frame-container"><div data-testid="cell-frame-title">
        <span title="Ada Example">Ada Example</span></div></div></div>
    </div></div>
    <div id="main">
      <header><span data-testid="conversation-info-header-chat-title">Ada Example</span></header>
      <div tabindex="-1"><div><span dir="auto">14/10/2026</span></div></div>
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
      <div role="row"><div data-id="MSG3"><div>
        <span data-testid="selectable-text">Thanks</span><div data-testid="msg-meta">1:05 pm
          <svg><title>wds-ic-read</title></svg></div></div></div></div>
      <div role="row"><div data-id="MSG4"><div data-virtualized="true"></div></div></div>
      <div role="row"><div data-id="MSG5"><div class="message-in">
        <div role="button" id="photo"><img data-testid="image-thumb" alt="" src="data:,"></div>
        <div data-testid="msg-meta">1:06 pm</div></div></div></div>
      <footer><div contenteditable="true" role="textbox"></div><button aria-label="Send">Send</button></footer>
    </div>
    <script>
      document.querySelector("header").setAttribute("data-testid", "conversation-info-header");
      // The search box: shows the matching chats in place of the list, as WhatsApp does.
      const grid = document.querySelector("#pane-side [role=grid]");
      const list = grid.innerHTML;
      const row = n => '<div role="row"><div data-testid="cell-frame-container"><div data-testid="cell-frame-title">'
        + '<span title="' + n + '">' + n + '</span></div></div></div>';
      document.querySelector("#side input").addEventListener("input", e => {
        const q = e.target.value.toLowerCase();
        const names = ["Grace Example", "🐒 Grace Sample"];
        grid.innerHTML = q ? names.filter(n => n.toLowerCase().includes(q)).map(row).join("") : list;
      });
      document.getElementById("pane-side").addEventListener("click", e => {
        const title = e.target.closest("[data-testid=cell-frame-container]")?.querySelector("span[title]");
        // Emoji become images in WhatsApp's header.
        if (title) document.querySelector("[data-testid=conversation-info-header-chat-title]").innerHTML =
          title.title.replace("🐒", '<img alt="🐒" src="data:,">');
      });
      document.querySelector("header").addEventListener("click", () => {
        const d = document.createElement("div");
        d.setAttribute("data-testid", "chat-info-drawer");
        d.innerHTML = '<button aria-label="Close"></button>'
          + '<span data-testid="contact-info-subtitle selectable-text">Ada Example</span>'
          + '<span data-testid="selectable-text"><span>+1 555 0100 000</span></span>'
          + '<div><div><span>About</span></div><span dir="auto">Testing things</span></div>';
        d.querySelector("button").addEventListener("click", () => d.remove());
        document.body.appendChild(d);
      });
      const viewer = what => () => {
        const modal = document.createElement("div");
        modal.setAttribute("data-testid", "media-viewer-modal");
        modal.innerHTML = '<button aria-label="Download"></button><div aria-label="Close"></div>';
        modal.querySelector("button").addEventListener("click", () => { document.body.dataset.downloaded = what; });
        // Like WhatsApp, the viewer takes a moment to go.
        modal.querySelector("[aria-label=Close]").addEventListener("click", () => setTimeout(() => modal.remove(), 150));
        document.body.appendChild(modal);
      };
      document.querySelector("footer button").addEventListener("click", () => {
        const box = document.querySelector("footer [contenteditable]");
        document.body.dataset.sent = box.innerText;
        box.innerHTML = "";
      });
      document.querySelector('[data-testid="document-thumb"]').addEventListener("click", viewer("document"));
      document.querySelector("#photo").addEventListener("click", viewer("photo"));
    </script>
    </body></html>
    """

    @MainActor
    func loadFixture() async throws -> WKWebView {
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
        let day = "14/10/2026"
        XCTAssertEqual(response.messages, [
            AgentMessage(
                id: "MSG1", direction: "in", sender: "Ada Example", stamp: "1:03 pm, 14/10/2026", time: "1:03 pm",
                day: day, date: day, text: "Here is the summary", document: nil
            ),
            AgentMessage(
                id: "MSG2", direction: "in", sender: "Ada Example", stamp: "", time: "1:04 pm", day: day, date: day,
                text: "", document: AgentDocument(name: "Test plan.pdf", type: "PDF", details: "4 pages • PDF • 10 kB")
            ),
            AgentMessage(
                id: "MSG3", direction: "out", sender: "", stamp: "", time: "1:05 pm", day: day, date: day, text: "Thanks",
                document: nil
            ),
            AgentMessage(
                id: "MSG4", direction: "", sender: "", stamp: "", time: "", day: day, date: day, text: "", document: nil,
                rendered: false
            ),
            AgentMessage(
                id: "MSG5", direction: "in", sender: "Ada Example", stamp: "", time: "1:06 pm", day: day, date: day,
                text: "", document: nil, media: "image"
            )
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
        XCTAssertEqual(pressed, "document")
        _ = try await PageReaders.run(WhatsAppScripts.closeViewer, in: webView)
        let open = try await webView
            .evaluateJavaScript("document.querySelectorAll('[data-testid=media-viewer-modal]').length") as? Int
        XCTAssertEqual(open, 0)
    }

    @MainActor
    func testDownloadClosesAnOpenViewerBeforePressingDownload() async throws {
        let webView = try await loadFixture()
        // A viewer left open by an earlier download must not have its button pressed again.
        _ = try await webView.evaluateJavaScript("document.querySelector('[data-testid=document-thumb]').click()")
        let result = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.download,
            arguments: ["id": "MSG5"],
            in: webView
        ))
        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.kind, "image")
        let pressed = try await webView.evaluateJavaScript("document.body.dataset.downloaded") as? String
        XCTAssertEqual(pressed, "photo")
        let closed = try await WhatsAppScripts.decode(PageReaders.run(WhatsAppScripts.closeViewer, in: webView))
        XCTAssertTrue(closed.ok)
        let open = try await webView
            .evaluateJavaScript("document.querySelectorAll('[data-testid=media-viewer-modal]').length") as? Int
        XCTAssertEqual(open, 0)
    }

    func testSavedFileMustBeTheExpectedDocument() {
        XCTAssertTrue(AgentResponder.sameFile("Test plan.pdf", saved: "Test plan.pdf"))
        XCTAssertTrue(AgentResponder.sameFile("Test plan.pdf", saved: "Test plan 1.pdf"))
        XCTAssertTrue(AgentResponder.sameFile("Plan 2.pdf", saved: "Plan 2.pdf"))
        XCTAssertTrue(AgentResponder.sameFile("", saved: "WhatsApp Image.jpeg"))
        XCTAssertFalse(AgentResponder.sameFile("Test plan.pdf", saved: "Other plan.pdf"))
        XCTAssertFalse(AgentResponder.sameFile("Test plan.pdf", saved: "Test plan.docx"))
    }

    @MainActor
    func testHistoryScrollsBackAndReadsEveryMessage() async throws {
        let rows = (1 ... 12).map {
            #"<div style="height:60px"><div data-id="H\#($0)"><span data-testid="selectable-text">Note \#($0)</span>"#
                + #"<div data-testid="msg-meta">1:\#(String(format: "%02d", $0)) pm</div></div></div>"#
        }.joined()
        let html = """
        <html><body><div id="main"><header><span data-testid="conversation-info-header-chat-title">Ada Example</span></header>
        <div id="pane" style="height:200px;overflow-y:auto">\(rows)</div></div>
        <script>
        // Like WhatsApp: rows out of view are emptied, except the newest, which stays drawn.
        const p = document.getElementById("pane");
        const rows = Array.from(p.querySelectorAll("[data-id]"));
        const draw = () => rows.forEach((row, i) => {
          const box = row.getBoundingClientRect(), view = p.getBoundingClientRect();
          const hidden = i < rows.length - 1 && (box.bottom < view.top || box.top > view.bottom);
          const mark = row.querySelector("[data-virtualized]");
          if (hidden && !mark) row.insertAdjacentHTML("afterbegin", '<div data-virtualized="true"></div>');
          if (!hidden && mark) mark.remove();
        });
        p.addEventListener("scroll", draw);
        p.scrollTop = p.scrollHeight;
        draw();
        </script></body></html>
        """
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(html, baseURL: URL(string: "https://example.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let response = try await WhatsAppScripts.messagesResponse(json: PageReaders.run(
            WhatsAppScripts.history, arguments: ["screens": 6], in: webView
        ))
        XCTAssertEqual(response.messages?.map(\.id), (1 ... 12).map { "H\($0)" })
        let atBottom = try await webView.evaluateJavaScript(
            "(p => p.scrollTop + p.clientHeight >= p.scrollHeight - 2)(document.getElementById('pane'))"
        ) as? Bool
        XCTAssertEqual(atBottom, true)
    }

    func testDayDividersBecomeDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        // Thursday 15 October 2026, midday.
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
        let british = Locale(identifier: "en_GB")
        func date(_ day: String) -> String {
            WhatsAppScripts.date(ofDay: day, now: now, calendar: calendar, locale: british)
        }
        XCTAssertEqual(date("Today"), "15/10/2026")
        XCTAssertEqual(date("Yesterday"), "14/10/2026")
        XCTAssertEqual(date("Friday"), "09/10/2026")
        XCTAssertEqual(date("Thursday"), "15/10/2026")
        XCTAssertEqual(date("27/09/2026"), "27/09/2026")
        XCTAssertEqual(date("3 unread messages"), "")
        XCTAssertEqual(date("Encrypted"), "")
    }

    func testDatesComeFromStampsOrAgreeingNeighbours() {
        func message(_ id: String, _ stamp: String) -> AgentMessage {
            AgentMessage(id: id, direction: "in", sender: "", stamp: stamp, time: "", text: "", document: nil)
        }
        let dated = WhatsAppScripts.datedMessages([
            message("A", ""), message("B", "9:00 am, 01/09/2026"), message("C", ""),
            message("D", "5:00 pm, 01/09/2026"), message("E", ""), message("F", "8:00 am, 03/09/2026")
        ])
        XCTAssertEqual(dated.map(\.date), [nil, "01/09/2026", "01/09/2026", "01/09/2026", nil, "03/09/2026"])
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
        XCTAssertEqual(missing.reason, "that message is not in the open chat")
    }

    @MainActor
    func testOpenFindsAChatThroughSearchAndClearsIt() async throws {
        let webView = try await loadFixture()
        let result = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "🐒 Grace Sample"],
            in: webView
        ))
        XCTAssertTrue(result.ok, result.reason ?? "")
        XCTAssertEqual(result.chat, "🐒 Grace Sample")
        let search = try await webView.evaluateJavaScript("document.querySelector('#side input').value") as? String
        XCTAssertEqual(search, "")
        let missing = try await WhatsAppScripts.decode(PageReaders.run(
            WhatsAppScripts.open,
            arguments: ["name": "Grace"],
            in: webView
        ))
        XCTAssertEqual(missing.reason, "no chat with that exact name; search found: Grace Example | 🐒 Grace Sample")
    }

    @MainActor
    func testContactOpensReadsAndClosesThePanel() async throws {
        let webView = try await loadFixture()
        let result = try await WhatsAppScripts.decode(PageReaders.run(WhatsAppScripts.contact, in: webView))
        XCTAssertEqual(result.contact, AgentContact(name: "Ada Example", phone: "+1 555 0100 000", about: "Testing things"))
        let open = try await webView
            .evaluateJavaScript("document.querySelectorAll('[data-testid=chat-info-drawer]').length") as? Int
        XCTAssertEqual(open, 0)
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
