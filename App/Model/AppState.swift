import Foundation

/// Everything that is saved to disk. `schemaVersion` lets a later release migrate old files.
/// Version 2 added `settings` and `Tab.muted`. Version 3 added `split`, sleep (`Tab.allowSleep`, `Tab.lastURL`,
/// the sleep setting) and the link, card-order and split-ratio settings.
struct AppState: Codable, Equatable, Sendable {
    static let currentVersion = 3

    var schemaVersion = AppState.currentVersion
    var profiles: [Profile] = []
    var tabs: [Tab] = []
    var selectedTabId: UUID?
    var settings = AppSettings()
    /// Nil when one tab fills the window. While set, `selectedTabId` is the focused side's tab.
    var split: SplitState?

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
    mutating func addTab(
        service: Service, name: String? = nil, url: String? = nil, newAccount: Bool = false, incognito: Bool = false
    ) -> Tab {
        if incognito {
            return addIncognitoTab(service: service, name: name, url: url)
        }
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
            colorHex: TabPalette.colors[tabs.count % TabPalette.colors.count],
            allowSleep: ServiceCatalog.allowsSleepByDefault(serviceId: service.id)
        )
        tabs.append(tab)
        select(tab.id)
        return tab
    }

    /// A tab with no profile: its web view gets a throwaway data store and the tab is not saved.
    private mutating func addIncognitoTab(service: Service, name: String?, url: String?) -> Tab {
        let tab = Tab(
            id: UUID(), serviceId: service.id, profileId: Self.incognitoProfile, customName: name, customURL: url,
            colorHex: TabPalette.colors[tabs.count % TabPalette.colors.count], allowSleep: false, incognito: true
        )
        tabs.append(tab)
        select(tab.id)
        return tab
    }

    static let incognitoProfile = "incognito"

    /// A tab opened from a link ("In Tabchat"): same profile as the page it came from, shown after it, not saved.
    @discardableResult
    mutating func addTemporaryTab(url: URL, after source: Tab) -> Tab {
        let tab = Tab(
            id: UUID(), serviceId: ServiceCatalog.custom.id, profileId: source.profileId,
            customName: url.host ?? "Link", customURL: url.absoluteString, colorHex: source.colorHex,
            allowSleep: false, incognito: source.incognito, temporary: true
        )
        let index = tabs.firstIndex { $0.id == source.id }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: index)
        select(tab.id)
        return tab
    }

    /// A copy of a tab right after it: same service and profile, so the same sign-in.
    @discardableResult
    mutating func duplicateTab(_ id: UUID, at url: String? = nil) -> Tab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = tabs[index]
        copy.id = UUID()
        copy.lastURL = url ?? copy.lastURL
        tabs.insert(copy, at: index + 1)
        select(copy.id)
        return copy
    }

    // MARK: Selection and split view

    mutating func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if var current = split {
            current.select(id)
            split = current
            selectedTabId = current.focusedId
        } else {
            selectedTabId = id
        }
    }

    /// Tabs whose web views are on screen.
    var visibleIds: [UUID] {
        split?.ids ?? selectedTabId.map { [$0] } ?? []
    }

    /// The tab that joins the selected one when split view opens without a choice: the next in the sidebar.
    func defaultSplitPartner() -> UUID? {
        guard tabs.count > 1, let selected = selectedTabId, let index = tabs.firstIndex(where: { $0.id == selected })
        else { return nil }
        return tabs[(index + 1) % tabs.count].id
    }

    /// Shows `other` beside the selected tab (or the next tab when `other` is nil or already selected).
    mutating func openSplit(with other: UUID? = nil) {
        if var current = split {
            if let other, tabs.contains(where: { $0.id == other }) {
                current.place(other)
                split = current
                selectedTabId = current.focusedId
            }
            return
        }
        guard let selected = selectedTabId else { return }
        let partner = other.flatMap { $0 == selected ? nil : $0 } ?? defaultSplitPartner()
        guard let partner, partner != selected, tabs.contains(where: { $0.id == partner }) else { return }
        split = SplitState(left: selected, right: partner, focus: .right)
        selectedTabId = partner
    }

    /// Back to one tab: the one with the focus.
    mutating func closeSplit() {
        split = nil
    }

    mutating func toggleSplit() {
        if split == nil {
            openSplit()
        } else {
            closeSplit()
        }
    }

    mutating func focusSplit(_ side: SplitState.Side) {
        guard var current = split else { return }
        current.focus = side
        split = current
        selectedTabId = current.focusedId
    }

    /// The state as it goes to disk: incognito and temporary tabs are dropped, and a split that
    /// involved one is closed on the tab that stays.
    func persisted() -> AppState {
        let dropped = Set(tabs.filter(\.isEphemeral).map(\.id))
        guard !dropped.isEmpty else { return self }
        var copy = self
        copy.tabs.removeAll { dropped.contains($0.id) }
        if let split, !dropped.isDisjoint(with: split.ids) {
            copy.split = nil
            copy.selectedTabId = split.ids.first { !dropped.contains($0) }
        }
        if let selected = copy.selectedTabId, dropped.contains(selected) {
            copy.selectedTabId = copy.tabs.first?.id
        }
        return copy
    }

    mutating func removeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if let current = split, current.contains(id) {
            split = nil
            selectedTabId = current.partner(of: id)
        } else if selectedTabId == id {
            selectedTabId = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Puts a previously removed tab back (at its old position if it still exists) and selects it.
    mutating func restoreTab(_ tab: Tab, at index: Int) {
        guard !tabs.contains(where: { $0.id == tab.id }) else { return }
        tabs.insert(tab, at: min(max(index, 0), tabs.count))
        select(tab.id)
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

/// Older files are upgraded on load: missing keys take defaults, then the version is raised so the
/// next save writes the current schema.
extension AppState {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profiles = try values.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        tabs = try values.decodeIfPresent([Tab].self, forKey: .tabs) ?? []
        selectedTabId = try values.decodeIfPresent(UUID.self, forKey: .selectedTabId)
        settings = try values.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        split = try values.decodeIfPresent(SplitState.self, forKey: .split)
        // A split that points at tabs that no longer exist is dropped rather than shown half empty.
        if let current = split,
           current.left == current.right || !current.ids.allSatisfy({ id in tabs.contains { $0.id == id } }) {
            split = nil
        }
        if let current = split {
            selectedTabId = current.focusedId
        }
    }
}
