import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettings()
                .tabItem { Label("Notifications", systemImage: "bell") }
            SleepSettings()
                .tabItem { Label("Sleep", systemImage: "moon.zzz") }
            LinkSettings()
                .tabItem { Label("Links", systemImage: "link") }
            AgentSettings()
                .tabItem { Label("Agents", systemImage: "terminal") }
        }
        .frame(width: 460, height: 420)
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

private struct SleepSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Sleep after", selection: Binding(
                    get: { model.state.settings.sleepAfterMinutes }, set: { model.setSleepAfter($0) }
                )) {
                    ForEach(SleepAfter.options, id: \.self) { Text(SleepAfter.label($0)).tag($0) }
                }
                Text("A service you have not looked at for this long gives up its page to free memory. "
                    + "It shows dimmed with a moon, and comes back where you left it when you select it.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("A sleeping service posts no notifications and its unread count stops updating. "
                    + "That is why WhatsApp, Discord, Teams and Outlook start with sleep off.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Allow sleep per service") {
                ForEach(model.tabs.filter { !$0.isEphemeral }) { tab in
                    Toggle(tab.displayName, isOn: Binding(
                        get: { tab.allowSleep }, set: { model.setAllowSleep(tab.id, $0) }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LinkSettings: View {
    @Environment(AppModel.self) private var model
    @State private var browsers: [BrowserApp] = []

    var body: some View {
        let current = model.state.settings.linkTarget
        Form {
            Section("Open links to other sites in") {
                Picker("Open in", selection: Binding(get: { current }, set: { model.setLinkTarget($0) })) {
                    Text("Default browser").tag(LinkTarget.defaultBrowser)
                    ForEach(browsers) { Text($0.name).tag(LinkTarget.browser($0.id)) }
                    if case let .browser(id) = current, !browsers.contains(where: { $0.id == id }) {
                        Text("Unavailable browser").tag(current)
                    }
                    Text("In Tabchat").tag(LinkTarget.inTabchat)
                }
                Text("\"In Tabchat\" opens a temporary tab with the same sign-in, next to the page. "
                    + "It is not saved. Links within a service, and sign-in pages, always stay in the service. "
                    + "mailto: and similar links go to their usual app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { browsers = Browsers.installed() }
    }
}

private struct AgentSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let on = model.state.settings.agentAccess
        Form {
            Section {
                Toggle("Let local agents read chosen services", isOn: Binding(
                    get: { on }, set: { model.setAgentAccess($0) }
                ))
                Text("Agents on this Mac (Claude Code and others) can then read the services ticked below "
                    + "through the tabchat-agent command: unread counts, notifications and what the page shows. "
                    + "Read only: they cannot send, click or open chats. Any program running as you can use it.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.agent.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Readable by agents") {
                ForEach(model.tabs.filter { !$0.isEphemeral }) { tab in
                    Toggle(tab.displayName, isOn: Binding(
                        get: { tab.agentReadable }, set: { model.setAgentReadable(tab.id, $0) }
                    ))
                }
            }
            .disabled(!on)
            Section {
                Button("Show Call Log") {
                    NSWorkspace.shared.activateFileViewerSelecting([AgentLog().fileURL])
                }
                Text("Each call is logged with the program, the service and how many items it read, never "
                    + "the content. Kept 30 days.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
