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
    private(set) var unread: [UUID: Int] = [:]
    private(set) var icons: [String: NSImage] = [:]
    var toast: String?

    @ObservationIgnored private let stateStore = StateStore()
    @ObservationIgnored private let iconStore = IconStore()
    @ObservationIgnored private let network = NetworkMonitor()
    @ObservationIgnored private var dataStores: [String: WKWebsiteDataStore] = [:]
    @ObservationIgnored private var toastTask: Task<Void, Never>?
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
        save()
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
        controllers[id]?.tearDown()
        controllers[id] = nil
        unread[id] = nil
        mutate { $0.removeTab(id) }
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

    /// Brings the window forward, e.g. when a notification is clicked.
    func reveal(_ id: UUID) {
        select(id)
        NSApp.activate()
        for window in NSApp.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Reports from tab controllers

    func setUnread(_ id: UUID, _ count: Int) {
        if unread[id] != count {
            unread[id] = count
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
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? tab.displayName : title
        content.subtitle = tab.displayName
        content.body = body
        content.sound = .default
        content.userInfo = ["tab": tab.id.uuidString]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        ))
    }
}
