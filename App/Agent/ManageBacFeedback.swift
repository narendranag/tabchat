import Foundation
import WebKit

/// ManageBac `feedback`: the teacher's annotations on a submitted file. A task page's "View Teacher
/// Feedback" button names `/document_previews/modal/<token>`; that answer (a script) carries the
/// document's id, a short-lived token and the document server (PSPDFKit, on `pspdfkit-*.prod.faria.co`).
/// The reader loads PSPDFKit's own viewer script, headless and read-only, in a hidden web view, asks it
/// for each page's annotations and their comment threads, and closes it. It never saves, edits or
/// creates anything (the viewer's auto-save is off), and nothing else on the document server is
/// fetched. The owner approved this widening on 2026-10-16 (DECISIONS.md).
enum ManageBacFeedback {
    /// PSPDFKit's viewer script, as every ManageBac page names it (`data-pspdf-kit-script`).
    static let sdk = URL(string: "https://assets.prod.faria.co/pspdfkit.js")!
    static let maxAnnotations = 2000
    static let maxText = 5000

    /// What the modal hands the viewer.
    struct Viewer: Equatable {
        var name: String
        var server: URL
        var documentId: String
        var token: String
        /// The document server's annotated PDF, for `--save`.
        var annotatedPDF: URL?
    }

    /// The document server: `https://pspdfkit-<region>.prod.faria.co/`.
    static func isDocumentServer(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.port == nil, url.user == nil, let host = url.host?.lowercased() else {
            return false
        }
        return host.range(of: #"^pspdfkit-[a-z0-9-]+\.prod\.faria\.co$"#, options: .regularExpression) != nil
    }

    /// The viewer's settings, read from the modal's script; nil when it holds no document.
    static func viewer(modal: String) -> Viewer? {
        func attribute(_ name: String) -> String? {
            let pattern = "data-\(name)=\\\\?['\"]([^'\"\\\\]*)"
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: modal, range: NSRange(modal.startIndex..., in: modal)),
                  let range = Range(match.range(at: 1), in: modal)
            else { return nil }
            return entities(String(modal[range]))
        }
        guard let serverText = attribute("server-url"), let server = URL(string: serverText), isDocumentServer(server),
              server.path == "/" || server.path.isEmpty,
              let documentId = attribute("document-id"),
              documentId.range(of: #"^[A-Za-z0-9_-]{1,100}$"#, options: .regularExpression) != nil,
              let token = attribute("preview-token"),
              token.range(of: #"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
        else { return nil }
        let annotated = attribute("download-annotated-url").flatMap(URL.init(string:)).flatMap { url in
            url.host?.lowercased() == server.host?.lowercased() && url.path == "/documents/\(documentId)/pdf" ? url : nil
        }
        return Viewer(
            name: title(modal) ?? "", server: server, documentId: documentId, token: token, annotatedPDF: annotated
        )
    }

    /// The modal's heading: the file's name.
    private static func title(_ modal: String) -> String? {
        guard let range = modal.range(of: #"<h3>(.*?)<\\?/h3>"#, options: .regularExpression) else { return nil }
        let inner = modal[range].replacingOccurrences(of: #"^<h3>|<\\?/h3>$"#, with: "", options: .regularExpression)
        let unescaped = inner.replacingOccurrences(of: #"\\(['"\\/])"#, with: "$1", options: .regularExpression)
        return entities(unescaped).trimmingCharacters(in: .whitespaces)
    }

    private static func entities(_ text: String) -> String {
        [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    /// Loads the viewer for `viewer` in a hidden web view at `origin` and reads it.
    @MainActor
    static func read(_ viewer: Viewer, origin: URL, dataStore: WKWebsiteDataStore) async throws -> AgentResponse {
        let hidden = HiddenWebView(dataStore: dataStore)
        defer { hidden.close() }
        hidden.webView.loadHTMLString(page, baseURL: origin)
        for _ in 0 ..< 100 where hidden.webView.isLoading || hidden.webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let arguments: [String: Any] = [
            "sdk": sdk.absoluteString, "serverUrl": viewer.server.absoluteString, "documentId": viewer.documentId,
            "jwt": viewer.token, "maxAnnotations": maxAnnotations, "maxText": maxText
        ]
        // The page's timers run slowly in a window that is never shown, so the waiting is done here:
        // up to a minute for the script to load and the viewer to answer.
        for _ in 0 ..< 240 {
            let json = try await PageReaders.run(step, arguments: arguments, in: hidden.webView, seconds: 5, contentWorld: .page)
            guard let state = try? JSONDecoder().decode(Step.self, from: Data(json.utf8)) else {
                return .failure("the feedback reader returned something unreadable")
            }
            if state.state == "error" {
                return .failure("the feedback viewer failed: \(state.reason ?? "no reason given")")
            }
            if let result = state.result {
                return response(result, viewer: viewer)
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        return .failure("the feedback viewer did not answer within a minute")
    }

    struct Collected: Decodable {
        var pages: Int
        var pageSizes: [AgentPageSize]
        var annotations: [AgentAnnotation]
        var truncated: Bool
    }

    private struct Step: Decodable {
        var state: String
        var reason: String?
        var result: Collected?
    }

    static func response(_ result: Collected, viewer: Viewer) -> AgentResponse {
        var response = AgentResponse(ok: true, untrusted: true)
        response.feedback = AgentFeedback(
            name: viewer.name, pages: result.pages, pageSizes: result.pageSizes, annotations: result.annotations,
            truncated: result.truncated
        )
        return response
    }

    /// An empty page on the tab's own origin, for the viewer to run in.
    static let page = "<!doctype html><html><head><meta charset=utf-8></head>"
        + "<body><div id=viewer style=\"width:1000px;height:1300px\"></div></body></html>"

    /// Run again and again until it reports `done` or `error`: loads the viewer's script, opens the
    /// document headless and read-only, then collects every page's annotations and comment threads.
    static let step = #"""
    const t = window.__tabchat || (window.__tabchat = {state: "new"});
    const strip = value => {
      if (value == null) return null;
      let text = typeof value === "object" ? (value.value ?? "") : String(value);
      if (/<[a-z]/i.test(text)) text = new DOMParser().parseFromString(text, "text/html").body.textContent || "";
      text = text.trim();
      return text ? text.slice(0, maxText) : null;
    };
    const iso = d => d instanceof Date && !isNaN(d) ? d.toISOString() : (typeof d === "string" ? d : null);
    const hex = c => c && typeof c.toHex === "function" ? c.toHex() : null;
    const collect = async inst => {
      const A = PSPDFKit.Annotations, pages = inst.totalPageCount, pageSizes = [], threads = {};
      for (let i = 0; i < pages; i++) {
        const info = inst.pageInfoForIndex(i);
        pageSizes.push({width: info.width, height: info.height});
      }
      if (typeof inst.getComments === "function") {
        try {
          (await inst.getComments()).forEach(c => {
            (threads[c.rootId] ||= [])
              .push({text: strip(c.text) || "", author: c.creatorName || null, created: iso(c.createdAt)});
          });
        } catch (e) {}
      }
      const annotations = [];
      let truncated = false;
      for (let i = 0; i < pages && !truncated; i++) {
        for (const a of (await inst.getAnnotations(i)).toArray()) {
          if (a instanceof A.LinkAnnotation || a instanceof A.WidgetAnnotation) continue;
          if (annotations.length >= maxAnnotations) { truncated = true; break; }
          const type = String(A.toSerializableObject(a).type || "").replace(/^pspdfkit\//, "").replace(/^(markup|shape)\//, "");
          let quoted = null;
          if (a instanceof A.TextMarkupAnnotation) {
            try { quoted = strip(await inst.getMarkupAnnotationText(a)); } catch (e) {}
          }
          const b = a.boundingBox, comments = (threads[a.id] || [])
            .sort((x, y) => String(x.created).localeCompare(String(y.created)));
          annotations.push({
            id: String(a.id), page: i + 1, type, rect: [b.left, b.top, b.width, b.height].map(n => Math.round(n * 10) / 10),
            text: strip(a.text) || strip(a.note), quoted, color: hex(a.color || a.strokeColor),
            author: a.creatorName || null, created: iso(a.createdAt), updated: iso(a.updatedAt),
            comments: comments.length ? comments : null
          });
        }
      }
      try { PSPDFKit.unload(inst); } catch (e) {}
      return {pages, pageSizes, annotations, truncated};
    };
    if (t.state === "new") {
      t.state = "script";
      const tag = document.createElement("script");
      tag.src = sdk;
      tag.onerror = () => { t.state = "error"; t.reason = "the viewer's script did not load"; };
      document.head.append(tag);
    } else if (t.state === "script" && typeof PSPDFKit !== "undefined") {
      t.state = "loading";
      PSPDFKit.load({
        serverUrl, documentId, authPayload: {jwt}, instant: true, container: "#viewer",
        baseUrl: new URL(`pspdfkit-web/${PSPDFKit.version}/`, sdk).href,
        autoSaveMode: PSPDFKit.AutoSaveMode.DISABLED,
        initialViewState: new PSPDFKit.ViewState({readOnly: true})
      }).then(inst => { t.inst = inst; t.state = "loaded"; t.waits = 0; })
        .catch(e => { t.state = "error"; t.reason = String((e && e.message) || e).slice(0, 300); });
    } else if (t.state === "loaded" && ++t.waits >= 12) {
      // Instant syncs the server's annotations just after the document opens: read them a few seconds on.
      t.state = "collecting";
      collect(t.inst).then(result => { t.result = result; t.state = "done"; })
        .catch(e => { t.state = "error"; t.reason = String((e && e.message) || e).slice(0, 300); });
    }
    return JSON.stringify({state: t.state, reason: t.reason || null, result: t.state === "done" ? t.result : null});
    """#
}
