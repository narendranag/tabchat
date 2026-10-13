import AppKit

/// Split view, tab sleep, duplicate, link routing, catalog cards and the Cmd+K palette.
extension AppModel {
    // MARK: Split view

    var split: SplitState? {
        state.split
    }

    var splitRatio: Double {
        state.settings.splitRatio
    }

    func openSplit(with other: UUID? = nil) {
        mutate { $0.openSplit(with: other) }
    }

    func closeSplit() {
        mutate { $0.closeSplit() }
    }

    func toggleSplit() {
        mutate { $0.toggleSplit() }
    }

    func focusSplit(_ side: SplitState.Side) {
        guard split?.focus != side else { return }
        mutate { $0.focusSplit(side) }
    }

    /// While dragging only the number changes; the file is written once, when the drag ends.
    func setSplitRatio(_ ratio: Double, commit: Bool) {
        state.settings.splitRatio = SplitMath.clamp(ratio)
        if commit {
            save()
        }
    }

    // MARK: Duplicate

    /// A new tab right after `id`, same service and profile (so the same sign-in), opened on the same page.
    func duplicate(_ id: UUID) {
        var copy: Tab?
        let url = controllers[id]?.webView.url?.absoluteString
        mutate { copy = $0.duplicateTab(id, at: url) }
        if let copy {
            createController(for: copy)
        }
    }

    // MARK: Sleep

    func setAllowSleep(_ id: UUID, _ allow: Bool) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.tabs[index].allowSleep = allow }
    }

    func setSleepAfter(_ minutes: Int) {
        mutate { $0.settings.sleepAfterMinutes = minutes }
    }

    /// Checks the idle timer every 30 seconds while the app runs.
    func startSleepTimer() {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.sleepTick()
            }
        }
    }

    func sleepTick() {
        let now = now()
        sleepClock.touch(state.visibleIds, at: now)
        sleepClock.track(state.tabs.map(\.id), at: now)
        let due = sleepClock.due(
            tabs: state.tabs, awake: { self.controllers[$0] != nil }, visible: Set(state.visibleIds),
            afterMinutes: state.settings.sleepAfterMinutes, now: now
        )
        for id in due {
            sleep(id)
        }
    }

    /// Releases the web view of a tab that is not on screen and remembers where it was.
    func sleep(_ id: UUID) {
        guard let controller = controllers[id], !state.visibleIds.contains(id) else { return }
        let url = controller.webView.url?.absoluteString
        controllers[id] = nil
        controller.tearDown()
        sleeping.insert(id)
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        mutate { $0.tabs[index].lastURL = url ?? $0.tabs[index].lastURL }
    }

    /// "Sleep Now": a tab on screen first gives way to another one.
    func sleepNow(_ id: UUID) {
        guard canSleepNow(id) else { return }
        if state.visibleIds.contains(id) {
            if let current = split, current.contains(id) {
                closeSplit()
            }
            if selection == id {
                selectRelative(1)
            }
        }
        sleep(id)
    }

    func canSleepNow(_ id: UUID) -> Bool {
        guard let tab = state.tabs.first(where: { $0.id == id }) else { return false }
        return !tab.isEphemeral && !sleeping.contains(id) && state.tabs.count > 1
    }

    /// Recreates a sleeping tab's web view at its last address.
    func wake(_ id: UUID) {
        guard sleeping.remove(id) != nil, let tab = state.tabs.first(where: { $0.id == id }) else { return }
        createController(for: tab)
    }

    // MARK: Links

    func setLinkTarget(_ target: LinkTarget) {
        mutate { $0.settings.linkTarget = target }
    }

    /// Sends a link that left the page to where the user wants it.
    func openExternal(_ url: URL, route: LinkPolicy.Route, from tab: Tab) {
        switch route {
        case .popup:
            break
        case .defaultBrowser:
            NSWorkspace.shared.open(url)
        case let .browser(bundleId):
            if !Browsers.open(url, bundleId: bundleId) {
                NSWorkspace.shared.open(url)
            }
        case .temporaryTab:
            var created: Tab?
            let source = state.tabs.first { $0.id == tab.id } ?? tab
            mutate { created = $0.addTemporaryTab(url: url, after: source) }
            if let created {
                createController(for: created)
            }
        }
    }

    // MARK: Catalog cards

    func toggleServiceHidden(_ id: String) {
        mutate { $0.settings.hiddenServices = CatalogLayout.toggled(id, in: $0.settings.hiddenServices) }
    }

    func moveService(_ id: String, before target: String) {
        mutate {
            $0.settings.serviceOrder = CatalogLayout.moved(
                id, before: target, services: ServiceCatalog.all, order: $0.settings.serviceOrder
            )
        }
    }

    // MARK: Quick switcher

    func showPalette() {
        MainWindow.shared.show()
        showingPalette = true
    }

    func paletteItems() -> [PaletteItem] {
        var items = state.tabs.map {
            PaletteItem.tab($0.id, title: $0.displayName, unread: unread[$0.id]?.count ?? 0, sleeping: sleeping.contains($0.id))
        }
        let hasTab = selectedTab != nil
        let paused = pause.isPaused(at: now())
        var actions: [PaletteAction] = [.newService]
        if hasTab {
            actions += [.reload, .find]
        }
        if state.tabs.count > 1 || split != nil {
            actions.append(.toggleSplit)
        }
        actions += [.pauseOneHour, .pauseUntilTomorrow]
        if paused {
            actions.append(.resume)
        }
        actions.append(.settings)
        if hasTab {
            actions.append(.duplicateTab)
        }
        if let id = selection, canSleepNow(id) {
            actions.append(.sleepTab)
        }
        items += actions.map(PaletteItem.action)
        return items
    }

    func run(_ item: PaletteItem) {
        showingPalette = false
        switch item.target {
        case let .tab(id): reveal(id)
        case let .action(action): perform(action)
        }
    }

    func perform(_ action: PaletteAction) {
        switch action {
        case .newService:
            MainWindow.shared.show()
            showingAdd = true
        case .reload: selectedController?.reload()
        case .find: selectedController?.showFind()
        case .toggleSplit: toggleSplit()
        case .pauseOneHour: pauseNotifications(.oneHour)
        case .pauseUntilTomorrow: pauseNotifications(.untilTomorrowMorning)
        case .resume: resumeNotifications()
        case .settings:
            NSApp.activate()
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .duplicateTab: selection.map(duplicate)
        case .sleepTab: selection.map(sleepNow)
        }
    }
}
