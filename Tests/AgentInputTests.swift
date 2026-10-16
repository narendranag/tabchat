import AppKit
import CoreGraphics
@testable import Tabchat
import XCTest

/// The owner's hardware input against an agent's synthetic events, with the values measured on
/// macOS 26 (DECISIONS.md, 2026-10-16).
final class AgentInputTests: XCTestCase {
    func testHardwareIsTheOwner() {
        // A real key, click or scroll: HID state, no source process, no user data.
        XCTAssertEqual(AgentInput.source(stateID: 1, pid: 0, userData: 0), .owner)
    }

    func testPostedEventsAreAnAgent() {
        // CGEvent with no source, then with a private source (System Events, cliclick).
        XCTAssertEqual(AgentInput.source(stateID: 0, pid: 30140, userData: 0), .agent)
        XCTAssertEqual(AgentInput.source(stateID: 1_687_926_652, pid: 30140, userData: 0), .agent)
        // A source made with hidSystemState gives state 1 too: the pid gives it away.
        XCTAssertEqual(AgentInput.source(stateID: 1, pid: 30140, userData: 0), .agent)
        // A tool that marks its events.
        XCTAssertEqual(AgentInput.source(stateID: 1, pid: 0, userData: 42), .agent)
    }

    func testAnEventMadeInThisProcessIsAnAgent() throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let cgEvent = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true))
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
        XCTAssertEqual(AgentInput.source(of: event), .agent)
    }

    func testStatusKeepsTheOwnerFieldAndAddsTheAgentOne() throws {
        let status = AgentStatus(
            focused: true, tabchatInputSecondsAgo: nil, agentInputSecondsAgo: 3,
            macIdleSeconds: 1, selectedTab: nil, sendPending: false
        )
        let json = try XCTUnwrap(String(data: AgentWire.encoder().encode(status), encoding: .utf8))
        XCTAssertEqual(json, #"{"agentInputSecondsAgo":3,"focused":true,"macIdleSeconds":1,"sendPending":false}"#)
    }

    func testRefusalsCarryRetryAfter() throws {
        var response = AgentResponse.failure("wait", code: .ownerActive)
        response.retryAfter = 95
        let json = try XCTUnwrap(String(data: AgentWire.encoder().encode(response), encoding: .utf8))
        XCTAssertTrue(json.contains(#""retryAfter":95"#), json)
    }
}
