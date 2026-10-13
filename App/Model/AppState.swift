import Foundation

/// Everything that is saved to disk. `schemaVersion` lets a later release migrate old files.
struct AppState: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var schemaVersion = AppState.currentVersion
    var profiles: [Profile] = []
    var tabs: [Tab] = []
    var selectedTabId: UUID?

    /// First launch: a few common services so the window is not empty.
    static func firstRun() -> AppState {
        var state = AppState()
        for id in ["whatsapp", "discord", "teams", "outlook-work"] {
            if let service = ServiceCatalog.service(id: id) {
                state.addTab(service: service)
            }
        }
        state.selectedTabId = state.tabs.first?.id
        return state
    }

    func profile(id: String) -> Profile? {
        profiles.first { $0.id == id }
    }

    /// Adds a tab. The first account of a service uses its default (possibly shared) profile; any
    /// further account of the same service gets a fresh profile, so its sign-in stays separate.
    @discardableResult
    mutating func addTab(service: Service, name: String? = nil, url: String? = nil, newAccount: Bool = false) -> Tab {
        let sameService = tabs.filter { $0.serviceId == service.id }
        let profileId: String
        var customName = name
        if sameService.isEmpty, !newAccount, service.kind == .builtIn {
            profileId = service.defaultProfile ?? "\(service.id)-1"
            ensureProfile(id: profileId, name: service.defaultProfileName ?? service.name)
        } else {
            let n = nextProfileNumber(prefix: service.id)
            profileId = "\(service.id)-\(n)"
            let label = name ?? service.name
            ensureProfile(id: profileId, name: sameService.isEmpty ? label : "\(label) \(n)")
            if customName == nil, !sameService.isEmpty {
                customName = "\(service.name) \(sameService.count + 1)"
            }
        }
        let tab = Tab(
            id: UUID(), serviceId: service.id, profileId: profileId, customName: customName, customURL: url,
            colorHex: TabPalette.colors[tabs.count % TabPalette.colors.count]
        )
        tabs.append(tab)
        selectedTabId = tab.id
        return tab
    }

    mutating func removeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabId == id {
            selectedTabId = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Moves `id` to the position of `target` (drag and drop in the sidebar).
    mutating func moveTab(_ id: UUID, before target: UUID) {
        guard id != target, let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: from)
        let to = tabs.firstIndex { $0.id == target } ?? tabs.count
        tabs.insert(tab, at: to)
    }

    private mutating func ensureProfile(id: String, name: String) {
        if profile(id: id) == nil {
            profiles.append(Profile(id: id, name: name))
        }
    }

    private func nextProfileNumber(prefix: String) -> Int {
        var n = 1
        while profile(id: "\(prefix)-\(n)") != nil {
            n += 1
        }
        return n
    }
}
