import Foundation

/// User preferences kept in the state file. "Start at login" is not here: macOS owns it (`LoginItem`).
struct AppSettings: Codable, Equatable, Sendable {
    var startHidden = false
    var showDockBadge = true
    var pause = NotificationPause()
}

/// Files written by older versions lack newer keys; each missing key takes its default.
extension AppSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startHidden = try values.decodeIfPresent(Bool.self, forKey: .startHidden) ?? false
        showDockBadge = try values.decodeIfPresent(Bool.self, forKey: .showDockBadge) ?? true
        pause = try values.decodeIfPresent(NotificationPause.self, forKey: .pause) ?? NotificationPause()
    }
}
