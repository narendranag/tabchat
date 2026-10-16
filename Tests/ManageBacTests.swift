@testable import Tabchat
import WebKit
import XCTest

/// ManageBac's `get`: paths, the stops, the pace and the page reader. Invented school and pages only:
/// this repo is public.
final class ManageBacTests: XCTestCase {
    private let origin = URL(string: "https://example-school.managebac.com")!

    private func path(_ text: String, save: Bool = false) -> String? {
        if case let .success(found) = ManageBac.path(text, origin: origin, save: save) {
            return found
        }
        return nil
    }

    func testPaths() {
        XCTAssertEqual(path("/parent"), "/parent")
        XCTAssertEqual(path("/parent/notifications?page=2#top"), "/parent/notifications?page=2")
        XCTAssertEqual(path("https://example-school.managebac.com/parent/classes/1"), "/parent/classes/1")
        XCTAssertEqual(path("/uploads/files/plan.pdf", save: true), "/uploads/files/plan.pdf")
        for refused in [
            "/student/tasks", "/parentx", "parent/tasks", "//evil.example/parent", "https://evil.example/parent",
            "http://example-school.managebac.com/parent", "https://other-school.managebac.com/parent",
            "/parent/../admin", "/parent/%2e%2e/admin", "/parent/logout", "/parent/sign_out", "/logout",
            "https://user@example-school.managebac.com/parent", "javascript:alert(1)", ""
        ] {
            XCTAssertNil(path(refused), refused)
        }
        XCTAssertNil(path("/sessions/sign_out", save: true))
        let cdn = "https://cdn.ca.managebac.com/uploads/asset/file/1/plan.pdf?Expires=1&Signature=abc"
        XCTAssertEqual(path(cdn, save: true), cdn)
        let bucket = "https://managebac-ca-prod.s3.ca-central-1.amazonaws.com/blobs/a/b?X-Amz-Expires=300"
        XCTAssertEqual(path(bucket, save: true), bucket)
        XCTAssertNil(path(cdn))
        for refused in [
            "https://cdn.ca.managebac.com/assets/app.js", "https://evil-managebac.s3.amazonaws.com/x",
            "https://managebac-ca-prod.s3.ca-central-1.amazonaws.com.evil.example/x", "http://cdn.ca.managebac.com/uploads/x"
        ] {
            XCTAssertNil(path(refused, save: true), refused)
        }
        XCTAssertTrue(ManageBac.isManageBac(URL(string: "https://example-school.managebac.com/parent")))
        XCTAssertFalse(ManageBac.isManageBac(URL(string: "https://managebac.com.evil.example/")))
        XCTAssertFalse(ManageBac.isManageBac(URL(string: "http://example-school.managebac.com/")))
    }

    func testTroubleStopsTheRun() throws {
        let page = try XCTUnwrap(URL(string: "https://example-school.managebac.com/parent"))
        XCTAssertNil(ManageBac.trouble(status: 200, finalURL: page, origin: origin, html: "<p>ok</p>"))
        XCTAssertNil(ManageBac.trouble(status: 404, finalURL: page, origin: origin, html: nil))
        let login = try XCTUnwrap(URL(string: "https://example-school.managebac.com/login"))
        XCTAssertEqual(ManageBac.trouble(status: 200, finalURL: login, origin: origin, html: nil)?.0, .signedOut)
        let sso = try XCTUnwrap(URL(string: "https://login.example-idp.invalid/saml"))
        XCTAssertEqual(ManageBac.trouble(status: 200, finalURL: sso, origin: origin, html: nil)?.0, .signedOut)
        XCTAssertEqual(ManageBac.trouble(status: 401, finalURL: page, origin: origin, html: nil)?.0, .signedOut)
        for status in [403, 429, 500, 503] {
            XCTAssertEqual(ManageBac.trouble(status: status, finalURL: page, origin: origin, html: nil)?.0, .checkpoint)
        }
        let challenge = "<html><head><title>Just a moment...</title></head></html>"
        XCTAssertEqual(ManageBac.trouble(status: 200, finalURL: page, origin: origin, html: challenge)?.0, .checkpoint)
    }

    func testFileRefusals() throws {
        let cdn = try XCTUnwrap(URL(string: "https://cdn.ca.managebac.com/uploads/asset/file/1/plan.pdf"))
        let login = try XCTUnwrap(URL(string: "https://example-school.managebac.com/login"))
        XCTAssertNil(ManageBac.fileRefusal(
            status: 200,
            mimeType: "application/pdf",
            url: cdn,
            expectedLength: 1000,
            origin: origin
        ))
        let expired = ManageBac.fileRefusal(status: 403, mimeType: "application/xml", url: cdn, expectedLength: 0, origin: origin)
        XCTAssertNotNil(expired)
        XCTAssertNil(expired?.stop)
        XCTAssertEqual(
            ManageBac.fileRefusal(status: 200, mimeType: "text/html", url: login, expectedLength: 0, origin: origin)?.stop?.0,
            .signedOut
        )
        XCTAssertEqual(
            ManageBac.fileRefusal(status: 429, mimeType: "text/plain", url: origin, expectedLength: 0, origin: origin)?.stop?.0,
            .checkpoint
        )
        let big = ManageBac.fileRefusal(
            status: 200,
            mimeType: "application/pdf",
            url: cdn,
            expectedLength: 30_000_000,
            origin: origin
        )
        XCTAssertEqual(big?.reason, "the file is larger than 25 MB")
    }

    func testGate() {
        var gate = ManageBac.Gate()
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(gate.refusal(now: start))
        XCTAssertEqual(gate.wait(now: start, jitter: 0.5), 0)
        gate.record(now: start)
        XCTAssertEqual(gate.wait(now: start, jitter: 0), 2, accuracy: 0.001)
        XCTAssertEqual(gate.wait(now: start, jitter: 1), 5, accuracy: 0.001)
        XCTAssertEqual(gate.wait(now: start.addingTimeInterval(10), jitter: 1), 0)
        gate.busy = true
        XCTAssertEqual(gate.refusal(now: start)?.code, "busy")
        gate.busy = false
        for second in 1 ..< ManageBac.budget {
            gate.record(now: start.addingTimeInterval(Double(second) * 3))
        }
        XCTAssertEqual(gate.refusal(now: start.addingTimeInterval(200))?.code, "rate")
        XCTAssertNil(gate.refusal(now: start.addingTimeInterval(ManageBac.window + 200)))
        gate.stop(.signedOut, "loggedOut: test", now: start)
        XCTAssertEqual(gate.refusal(now: start.addingTimeInterval(60))?.code, "signed-out")
        XCTAssertNil(gate.refusal(now: start.addingTimeInterval(ManageBac.haltFor + ManageBac.window + 1)))
    }

    private static let page = """
    <html><head><title>Notifications | ManageBac</title><script>var secret = 1;</script></head><body>
    <h1>Notifications</h1>
    <ul><li><a href="/parent/classes/1/tasks/2">New task: Essay draft</a> <span>Language and Literature</span></li>
    <li>Grade released: <b>Criterion A 6</b></li></ul>
    <table><tr><td>A</td><td>6</td></tr></table>
    </body></html>
    """

    @MainActor
    func testGetReadsTextAndHTML() async throws {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString("<html><body></body></html>", baseURL: URL(string: "https://example-school.managebac.invalid/"))
        for _ in 0 ..< 100 where webView.isLoading || webView.url == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        // A data: URL stands in for the server: the script's fetch and parsing run as they would live.
        let encoded = Self.page.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let json = try await PageReaders.run(ManageBac.get, arguments: [
            "path": "data:text/html," + encoded, "maxText": 50000, "maxHTML": 1_500_000
        ], in: webView)
        let fetched = try XCTUnwrap(JSONDecoder().decode(ManageBac.Fetched.self, from: Data(json.utf8)))
        XCTAssertEqual(fetched.status, 200)
        XCTAssertEqual(fetched.title, "Notifications | ManageBac")
        XCTAssertFalse(fetched.text.contains("secret"))
        XCTAssertTrue(fetched.text.contains("New task: Essay draft Language and Literature"), fetched.text)
        XCTAssertTrue(fetched.text.contains("Grade released: Criterion A 6"))
        XCTAssertTrue(fetched.html.contains("/parent/classes/1/tasks/2"))
        XCTAssertFalse(fetched.password)
    }

    func testResponses() {
        let json = #"{"ok":true,"url":"https://example-school.managebac.com/parent","status":200,"contentType":"text/html","#
            + #""title":"Home","challenged":false,"password":false,"text":"Hello","html":"<p>Hello</p>","truncated":false}"#
        let (response, problem) = ManageBac.response(json: json, origin: origin)
        XCTAssertNil(problem)
        XCTAssertEqual(response.untrusted, true)
        XCTAssertEqual(response.fetched?.text, "Hello")
        let login = json.replacingOccurrences(of: "/parent\"", with: "/login\"")
        XCTAssertEqual(ManageBac.response(json: login, origin: origin).0.code, "signed-out")
        let challenged = json.replacingOccurrences(of: "\"challenged\":false", with: "\"challenged\":true")
        XCTAssertEqual(ManageBac.response(json: challenged, origin: origin).1?.0, .checkpoint)
        let missing = json.replacingOccurrences(of: "\"status\":200", with: "\"status\":404")
        let (gone, stop) = ManageBac.response(json: missing, origin: origin)
        XCTAssertEqual(gone.code, "not-found")
        XCTAssertNil(stop)
    }

    func testManageBacIsABuiltInServiceThatStaysLoaded() {
        let service = ServiceCatalog.service(id: "managebac")
        XCTAssertEqual(service?.asksForURL, true)
        XCTAssertFalse(ServiceCatalog.allowsSleepByDefault(serviceId: "managebac"))
    }
}
