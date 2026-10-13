import AppKit
import Observation
import UserNotifications
import WebKit

enum AppEnvironment {
    /// The unit tests load the app as their host; it must not open web views then.
    static let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var state = AppState()
    private(set) var controllers: [UUID: TabController] = [:]
    private(set) var unread: [UUID: Unread] = [:]
    /// Tabs removed this session, newest last, for Reopen Closed Service. Not saved.
    private(set) var closedTabs: [ClosedTab] = []
    private(set) var startAtLogin = LoginItem.isEnabled
    private(set) var loginError: String?
    var showingAdd = false
    private(set) var icons: [String: NSImage] = [:]
    var toast: String?
    /// The tab list as the Services menu sees it; see `MenuState`.
    let menuState = MenuState()

    @ObservationIgnored private let stateStore = StateStore()
    @ObservationIgnored private let iconStore = IconStore()
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored private var dataStores: [String: WKWebsiteDataStore] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var pauseTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    var tabs: [Tab] {
        state.tabs
    }

    var selection: UUID? {
        state.selectedTabId
    }

    var selectedTab: Tab? {
        state.tabs.first { $0.id == state.selectedTabId }
    }

    var selectedController: TabController? {
        selection.flatMap { controllers[$0] }
    }

    // MARK: Lifecycle

    /// Idempotent: the window can be closed and reopened, which re-runs the root view's onAppear.
    func start() {
        guard !started else { return }
        started = true
        do {
            state = try stateStore.load() ?? AppState.firstRun()
        } catch {
            // Keep the unreadable file for inspection rather than overwriting it with defaults.
            let backup = stateStore.fileURL.appendingPathExtension("broken")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: stateStore.fileURL, to: backup)
            state = AppState.firstRun()
        }
        if state.settings.pause.until != nil, !state.settings.pause.isPaused(at: Date()) {
            state.settings.pause = NotificationPause()
        }
        save()
        schedulePauseEnd()
        updateBadges()
        // Every tab loads at launch so background tabs still deliver notifications and unread counts.
        for tab in state.tabs {
            createController(for: tab)
        }
        network.start { [weak self] in
            Task { @MainActor in self?.retryFailedTabs() }
        }
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.retryFailedTabs()
            }
        }
    }

    private func retryFailedTabs() {
        for controller in controllers.values where controller.loadError != nil {
            controller.retry()
        }
    }

    private func save() {
        menuState.update(from: state.tabs)
        try? stateStore.save(state)
    }

    private func mutate(_ change: (inout AppState) -> Void) {
        change(&state)
        save()
    }

    // MARK: Tabs

    func dataStore(for profileId: String) -> WKWebsiteDataStore {
        if let existing = dataStores[profileId] {
            return existing
        }
        let store = WKWebsiteDataStore(forIdentifier: StableUUID.make(profileId))
        dataStores[profileId] = store
        return store
    }

    private func createController(for tab: Tab) {
        let controller = TabController(tab: tab, dataStore: dataStore(for: tab.profileId), model: self)
        controllers[tab.id] = controller
        if let icon = iconStore.cached(key: tab.iconKey) {
            icons[tab.iconKey] = icon
        }
        controller.loadStartPage()
    }

    func addTab(service: Service, name: String? = nil, url: String? = nil, newAccount: Bool = false) {
        var tab: Tab?
        mutate { tab = $0.addTab(service: service, name: name, url: url, newAccount: newAccount) }
        if let tab {
            createController(for: tab)
        }
    }

    func addAnotherAccount(of tab: Tab) {
        addTab(service: tab.service, name: tab.customName.map(Self.stripNumber), url: tab.customURL, newAccount: true)
    }

    private static func stripNumber(_ name: String) -> String {
        String(name.reversed().drop { $0.isNumber }.drop { $0 == " " }.reversed())
    }

    func removeTab(_ id: UUID) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        closedTabs.append(ClosedTab(tab: state.tabs[index], index: index))
        controllers[id]?.tearDown()
        controllers[id] = nil
        unread[id] = nil
        mutate { $0.removeTab(id) }
        updateBadges()
    }

    /// Brings back the most recently removed tab with its profile (so it is still signed in).
    func reopenClosedTab() {
        guard let closed = closedTabs.popLast() else { return }
        mutate { $0.restoreTab(closed.tab, at: closed.index) }
        createController(for: closed.tab)
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.tabs[index].customName = trimmed.isEmpty ? nil : trimmed }
    }

    func move(_ id: UUID, before target: UUID) {
        mutate { $0.moveTab(id, before: target) }
    }

    func select(_ id: UUID) {
        guard state.tabs.contains(where: { $0.id == id }) else { return }
        mutate { $0.selectedTabId = id }
    }

    func select(index: Int) {
        guard state.tabs.indices.contains(index) else { return }
        select(state.tabs[index].id)
    }

    /// Moves the selection `offset` tabs along, wrapping at either end.
    func selectRelative(_ offset: Int) {
        guard !state.tabs.isEmpty else { return }
        let current = state.tabs.firstIndex { $0.id == state.selectedTabId } ?? 0
        let count = state.tabs.count
        select(index: ((current + offset) % count + count) % count)
    }

    /// Brings the window forward on a tab, e.g. when a notification or menu bar item is clicked.
    func reveal(_ id: UUID) {
        select(id)
        MainWindow.shared.show()
    }

    // MARK: Settings

    func setStartHidden(_ on: Bool) {
        mutate { $0.settings.startHidden = on }
    }

    func setShowDockBadge(_ on: Bool) {
        mutate { $0.settings.showDockBadge = on }
        updateBadges()
    }

    func setMuted(_ id: UUID, _ muted: Bool) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.tabs[index].muted = muted }
    }

    func refreshLoginItem() {
        startAtLogin = LoginItem.isEnabled
    }

    func setStartAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refreshLoginItem()
    }

    // MARK: Pause

    var pause: NotificationPause {
        state.settings.pause
    }

    func pauseNotifications(_ option: PauseOption) {
        mutate { $0.settings.pause = NotificationPause.make(option, now: Date(), calendar: .current) }
        schedulePauseEnd()
    }

    func resumeNotifications() {
        mutate { $0.settings.pause = NotificationPause() }
        schedulePauseEnd()
    }

    /// Clears the stored pause when its end date passes, so the menus drop "Paused until …".
    private func schedulePauseEnd() {
        pauseTask?.cancel()
        pauseTask = nil
        guard let until = state.settings.pause.until, !state.settings.pause.isIndefinite else { return }
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow) + 0.5))
            guard !Task.isCancelled, let self, state.settings.pause.until == until else { return }
            resumeNotifications()
        }
    }

    // MARK: Badges

    var totalUnread: Int {
        UnreadSummary.total(unread.values)
    }

    var anyUnread: Bool {
        UnreadSummary.anyUnread(unread.values)
    }

    private func updateBadges() {
        NSApp?.dockTile.badgeLabel = state.settings.showDockBadge ? UnreadSummary.dockLabel(total: totalUnread) : nil
    }

    // MARK: Reports from tab controllers

    func setUnread(_ id: UUID, _ value: Unread) {
        if unread[id] != value {
            unread[id] = value
            updateBadges()
        }
    }

    func fetchIcon(candidates: [URL], key: String) async {
        guard icons[key] == nil, let image = await iconStore.fetch(candidates: candidates, key: key) else { return }
        icons[key] = image
    }

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled {
                self?.toast = nil
            }
        }
    }

    func postNotification(title: String, body: String, from tab: Tab) {
        // Unread keeps updating while paused or muted; only the banner is suppressed. The tab is
        // looked up again because `tab` is a snapshot from when its controller was created.
        let current = state.tabs.first { $0.id == tab.id } ?? tab
        guard pause.allows(current, at: Date()) else { return }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? current.displayName : title
        content.subtitle = current.displayName
        content.body = body
        content.sound = .default
        content.threadIdentifier = current.id.uuidString
        content.userInfo = ["tab": current.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }
}

struct ClosedTab: Sendable {
    let tab: Tab
    let index: Int
}
