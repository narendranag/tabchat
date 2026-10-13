import SwiftUI

/// The menu bar item: the icon turns solid when anything is unread.
struct MenuBarIcon: View {
    let model: AppModel

    var body: some View {
        Image(systemName: model.anyUnread ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
    }
}

struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        ForEach(model.tabs) { tab in
            Button(UnreadSummary.menuTitle(name: tab.displayName, unread: model.unread[tab.id] ?? .none)) {
                model.reveal(tab.id)
            }
        }
        if model.tabs.isEmpty {
            Text("No services")
        }
        Divider()
        PauseMenu(model: model)
        Divider()
        Button("Open Tabchat") { MainWindow.shared.show() }
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Tabchat") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private struct PauseMenu: View {
    let model: AppModel

    var body: some View {
        let paused = model.pause.isPaused(at: Date())
        Menu(paused ? model.pause.status(now: Date(), calendar: .current) : "Pause notifications") {
            Button("For 1 hour") { model.pauseNotifications(.oneHour) }
            Button("Until tomorrow 08:00") { model.pauseNotifications(.untilTomorrowMorning) }
            Button("Until I turn it back on") { model.pauseNotifications(.untilOff) }
            Divider()
            Button("Resume") { model.resumeNotifications() }
                .disabled(!paused)
        }
    }
}
