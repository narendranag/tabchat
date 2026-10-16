@testable import Tabchat
import WebKit
import XCTest

/// ManageBac `feedback`: the modal's settings and the viewer reader. Invented documents only: this repo
/// is public.
final class ManageBacFeedbackTests: XCTestCase {
    /// Shaped like the modal's answer: a script that writes the viewer's HTML into the page.
    private static let modal = #"""
    {
        const modal = document.querySelector('#modal-box-wrapper')
        if (modal) modal.innerHTML = '<div class=\'modal fade\'>\n<h3>Essay &amp; draft.pdf<\/h3>\n'
          + '<a data-download-annotated-url=\'https://pspdfkit-xx.prod.faria.co/documents/DOC_abc-1/pdf?jwt=aaa.bbb.ccc\'><\/a>\n'
          + '<div data-pdf-preview-target=\'previewContainer\' data-document-id=\'DOC_abc-1\' data-preview-token=\'aaa.bbb.ccc\' '
          + 'data-server-url=\'https://pspdfkit-xx.prod.faria.co/\' data-timezone=\'Asia/Kolkata\'><\/div><\/div>'
    }
    """#

    func testViewerSettings() throws {
        let viewer = try XCTUnwrap(ManageBacFeedback.viewer(modal: Self.modal))
        XCTAssertEqual(viewer.name, "Essay & draft.pdf")
        XCTAssertEqual(viewer.documentId, "DOC_abc-1")
        XCTAssertEqual(viewer.token, "aaa.bbb.ccc")
        XCTAssertEqual(viewer.server.absoluteString, "https://pspdfkit-xx.prod.faria.co/")
        XCTAssertEqual(viewer.annotatedPDF?.path, "/documents/DOC_abc-1/pdf")
        for (from, to) in [
            ("data-server-url=\\'https://pspdfkit-xx", "data-server-url=\\'https://evil.example/x"),
            ("data-server-url=\\'https://", "data-server-url=\\'http://"),
            ("data-document-id=\\'DOC_abc-1\\'", "data-document-id=\\'../x\\'"),
            ("data-preview-token=\\'aaa.bbb.ccc\\'", "data-preview-token=\\'nope\\'")
        ] {
            XCTAssertNil(ManageBacFeedback.viewer(modal: Self.modal.replacingOccurrences(of: from, with: to)), to)
        }
        let elsewhere = Self.modal.replacingOccurrences(
            of: "https://pspdfkit-xx.prod.faria.co/documents", with: "https://evil.example/documents"
        )
        XCTAssertNil(ManageBacFeedback.viewer(modal: elsewhere)?.annotatedPDF)
        XCTAssertFalse(ManageBacFeedback.isDocumentServer(URL(string: "https://pspdfkit-xx.prod.faria.co.evil.example/")))
    }

    func testFeedbackCountsAgainstTheBudget() {
        var gate = ManageBac.Gate()
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(gate.left(now: start), ManageBac.budget)
        gate.record(now: start)
        gate.record(now: start)
        XCTAssertEqual(gate.left(now: start), ManageBac.budget - 2)
        XCTAssertEqual(gate.left(now: start.addingTimeInterval(ManageBac.window + 1)), ManageBac.budget)
    }

    /// A stand-in for PSPDFKit with the calls the reader makes, so the collecting runs as it would live.
    private static let fakeSDK = #"""
    class Annotation { constructor(o) { Object.assign(this, o); } }
    class TextMarkupAnnotation extends Annotation {}
    class LinkAnnotation extends Annotation {}
    const types = new Map();
    const make = (cls, type, o) => { const a = new cls(o); types.set(a, type); return a; };
    const pages = [
      [make(TextMarkupAnnotation, "pspdfkit/markup/highlight", {
        id: "a1", boundingBox: {left: 10.04, top: 20, width: 100, height: 12}, note: "Good point",
        creatorName: "Teacher", createdAt: new Date("2026-01-02T03:04:05Z"), color: {toHex: () => "#ffff00"}}),
       make(LinkAnnotation, "pspdfkit/link", {id: "l1", boundingBox: {left: 0, top: 0, width: 1, height: 1}})],
      [make(Annotation, "pspdfkit/text", {id: "a2", boundingBox: {left: 1, top: 2, width: 3, height: 4},
        text: {format: "xhtml", value: "<p>Cite <b>sources</b></p>"}, creatorName: "Teacher"})]
    ];
    const inst = {
      totalPageCount: 2,
      pageInfoForIndex: i => ({width: 595, height: 842}),
      getAnnotations: async i => ({toArray: () => pages[i]}),
      getMarkupAnnotationText: async a => "the highlighted words",
      getComments: async () => [{rootId: "a1", text: {value: "Expand this"}, creatorName: "Teacher",
        createdAt: new Date("2026-01-03T00:00:00Z")}]
    };
    window.PSPDFKit = {
      version: "1.0.0", AutoSaveMode: {DISABLED: "DISABLED"}, ViewState: class { constructor(o) { this.o = o; } },
      Annotations: {TextMarkupAnnotation, LinkAnnotation, WidgetAnnotation: class {},
        toSerializableObject: a => ({type: types.get(a)})},
      load: async options => { window.loadOptions = options; return inst; },
      unload: () => {}
    };
    window.__tabchat = {state: "script"};
    return "";
    """#

    @MainActor
    func testReaderCollectsAnnotations() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString(ManageBacFeedback.page, baseURL: URL(string: "https://example-school.managebac.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        _ = try await PageReaders.run(Self.fakeSDK, in: webView, contentWorld: .page)
        let arguments: [String: Any] = [
            "sdk": "https://assets.example.invalid/pspdfkit.js", "serverUrl": "https://pspdfkit-xx.example.invalid/",
            "documentId": "DOC", "jwt": "a.b.c", "maxAnnotations": 10, "maxText": 100
        ]
        var done: String?
        for _ in 0 ..< 40 {
            let json = try await PageReaders.run(ManageBacFeedback.step, arguments: arguments, in: webView, contentWorld: .page)
            if json.contains("\"state\":\"done\"") || json.contains("\"state\":\"error\"") {
                done = json
                break
            }
        }
        let json = try XCTUnwrap(done)
        XCTAssertFalse(json.contains("\"state\":\"error\""), json)
        struct Step: Decodable {
            var result: ManageBacFeedback.Collected
        }
        let result = try JSONDecoder().decode(Step.self, from: Data(json.utf8)).result
        XCTAssertEqual(result.pages, 2)
        XCTAssertEqual(result.pageSizes.first?.width, 595)
        XCTAssertEqual(result.annotations.count, 2)
        let highlight = result.annotations[0]
        XCTAssertEqual(highlight.type, "highlight")
        XCTAssertEqual(highlight.page, 1)
        XCTAssertEqual(highlight.rect, [10, 20, 100, 12])
        XCTAssertEqual(highlight.text, "Good point")
        XCTAssertEqual(highlight.quoted, "the highlighted words")
        XCTAssertEqual(highlight.color, "#ffff00")
        XCTAssertEqual(highlight.created, "2026-01-02T03:04:05.000Z")
        XCTAssertEqual(highlight.comments?.first?.text, "Expand this")
        let text = result.annotations[1]
        XCTAssertEqual(text.type, "text")
        XCTAssertEqual(text.page, 2)
        XCTAssertEqual(text.text, "Cite sources")
        let options = try await PageReaders.run(
            "return JSON.stringify([loadOptions.autoSaveMode, loadOptions.initialViewState.o.readOnly])",
            in: webView, contentWorld: .page
        )
        XCTAssertEqual(options, #"["DISABLED",true]"#)
    }
}
