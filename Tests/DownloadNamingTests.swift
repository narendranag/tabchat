@testable import Tabchat
import XCTest

final class DownloadNamingTests: XCTestCase {
    private let dir = URL(fileURLWithPath: "/tmp/dl")

    func testFreeNameIsKept() {
        let url = DownloadNaming.uniqueURL(in: dir, filename: "report.pdf") { _ in false }
        XCTAssertEqual(url.lastPathComponent, "report.pdf")
    }

    func testExistingNamesGetNumbered() {
        let taken: Set = ["report.pdf", "report 1.pdf"]
        let url = DownloadNaming.uniqueURL(in: dir, filename: "report.pdf") { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(url.lastPathComponent, "report 2.pdf")
    }

    func testNoExtensionAndPathStripping() {
        let url = DownloadNaming.uniqueURL(in: dir, filename: "../evil/notes") { $0.lastPathComponent == "notes" }
        XCTAssertEqual(url.lastPathComponent, "notes 1")
        XCTAssertEqual(url.deletingLastPathComponent().path, "/tmp/dl")
    }
}
