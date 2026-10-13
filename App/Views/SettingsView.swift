import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell") }
        }
        .frame(width: 440, height: 360)
        .onAppear { model.refreshLoginItem() }
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Toggle("Start at login", isOn: Binding(get: { model.startAtLogin }, set: { model.setStartAtLogin($0) }))
            if let error = model.loginError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Toggle("Start hidden (menu bar only)", isOn: Binding(
                get: { model.state.settings.startHidden }, set: { model.setStartHidden($0) }
            ))
            Text("Applies at every launch. Open the window from the menu bar or the Dock.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show unread count in Dock", isOn: Binding(
                get: { model.state.settings.showDockBadge }, set: { model.setShowDockBadge($0) }
            ))
        }
        .formStyle(.grouped)
    }
}

private struct NotificationSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let paused = model.pause.isPaused(at: Date())
        Form {
            Section("Pause") {
                HStack {
                    Text(model.pause.status(now: Date(), calendar: .current))
                    Spacer()
                    Menu("Pause") {
                        Button("For 1 hour") { model.pauseNotifications(.oneHour) }
                        Button("Until tomorrow 08:00") { model.pauseNotifications(.untilTomorrowMorning) }
                        Button("Until I turn it back on") { model.pauseNotifications(.untilOff) }
                    }
                    .fixedSize()
                    Button("Resume") { model.resumeNotifications() }.disabled(!paused)
                }
            }
            Section("Mute notifications per service") {
                ForEach(model.tabs) { tab in
                    Toggle(tab.displayName, isOn: Binding(
                        get: { tab.muted }, set: { model.setMuted(tab.id, $0) }
                    ))
                }
                if model.tabs.isEmpty {
                    Text("No services").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
