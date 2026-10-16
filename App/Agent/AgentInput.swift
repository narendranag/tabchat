import AppKit
import CoreGraphics

/// Whose hands an input event came from. Measured on macOS 26 (DECISIONS.md, 2026-10-16): the
/// keyboard, mouse and trackpad deliver events with source state `hidSystemState` (1), source
/// process 0 and user 0. Everything posted through `CGEvent` (cliclick, computer use, UI tests,
/// AppleScript's System Events) carries the posting process's pid and its user, whatever source
/// state it chose: a source made with `hidSystemState` gives state 1 too, so the pid is the test.
enum AgentInput: Equatable {
    case owner
    case agent

    /// LinkedIn and X actions wait this long after the owner's last input.
    static let ownerWindow: TimeInterval = 120

    static func source(stateID: Int64, pid: Int64, userData: Int64) -> AgentInput {
        let hardware = stateID == Int64(CGEventSourceStateID.hidSystemState.rawValue) && pid == 0 && userData == 0
        return hardware ? .owner : .agent
    }

    /// An event without a `CGEvent` behind it was made inside a process, never by a device.
    static func source(of event: NSEvent) -> AgentInput {
        guard let cgEvent = event.cgEvent else { return .agent }
        return source(
            stateID: cgEvent.getIntegerValueField(.eventSourceStateID),
            pid: cgEvent.getIntegerValueField(.eventSourceUnixProcessID),
            userData: cgEvent.getIntegerValueField(.eventSourceUserData)
        )
    }
}
