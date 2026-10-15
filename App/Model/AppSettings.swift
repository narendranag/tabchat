import Foundation

/// User preferences kept in the state file. "Start at login" is not here: macOS owns it (`LoginItem`).
struct AppSettings: Codable, Equatable, Sendable {
    var startHidden = false
    var showDockBadge = true
    var pause = NotificationPause()
    /// Minutes before an unselected tab sleeps; 0 = never. See `SleepAfter`.
    var sleepAfterMinutes = SleepAfter.standard
    var linkTarget = LinkTarget.defaultBrowser
    /// Built-in service ids hidden from the Add service sheet.
    var hiddenServices: [String] = []
    /// The user's card order in the Add service sheet; services not listed follow in catalog order.
    var serviceOrder: [String] = []
    /// Width share of the left pane in split view.
    var splitRatio = SplitMath.defaultRatio
    /// Local agents may read the tabs ticked for them (`Tab.agentReadable`). Off by default.
    var agentAccess = false
}

/// Files written by older versions lack newer keys; each missing key takes its default.
extension AppSettings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        startHidden = try values.decodeIfPresent(Bool.self, forKey: .startHidden) ?? false
        showDockBadge = try values.decodeIfPresent(Bool.self, forKey: .showDockBadge) ?? true
        pause = try values.decodeIfPresent(NotificationPause.self, forKey: .pause) ?? NotificationPause()
        sleepAfterMinutes = try values.decodeIfPresent(Int.self, forKey: .sleepAfterMinutes) ?? SleepAfter.standard
        linkTarget = try values.decodeIfPresent(LinkTarget.self, forKey: .linkTarget) ?? .defaultBrowser
        hiddenServices = try values.decodeIfPresent([String].self, forKey: .hiddenServices) ?? []
        serviceOrder = try values.decodeIfPresent([String].self, forKey: .serviceOrder) ?? []
        agentAccess = try values.decodeIfPresent(Bool.self, forKey: .agentAccess) ?? false
        splitRatio = try SplitMath.clamp(values.decodeIfPresent(Double.self, forKey: .splitRatio) ?? SplitMath.defaultRatio)
    }
}
