import SwiftUI
import WebKit
import UserNotifications

@main
struct SpikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = Model.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandMenu("Tabs") {
                ForEach(Array(allTabs.enumerated()), id: \.offset) { i, tab in
                    Button(tab.name) { model.selection = tab.id }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, err in
            Task { @MainActor in Model.shared.addLog("notification authorization granted=\(granted) error=\(String(describing: err))") }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let tab = response.notification.request.content.userInfo["tab"] as? String
        Task { @MainActor in
            if let tab {
                Model.shared.addLog("notification clicked -> \(tab)")
                Model.shared.select(tab)
            }
            completionHandler()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: Model

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                ForEach(allTabs) { tab in
                    HStack {
                        Text(tab.name)
                        Spacer()
                        if let n = model.unread[tab.id], n > 0 {
                            Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill(.red))
                        }
                    }.tag(tab.id)
                }
                Section("Tools") { Label("Diagnostics", systemImage: "list.bullet.rectangle").tag(diagnosticsID) }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            // One host keeps every web view in the window; overlays cover it for the other screens.
            ZStack {
                WebHost()
                if model.selection == diagnosticsID {
                    DiagnosticsView().background(.background)
                } else if let tab = selectedTab, model.url(for: tab) == nil {
                    BrightspacePrompt().background(.background)
                } else if selectedTab == nil {
                    Text("Pick a tab").frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
                }
            }
            .toolbar {
                if let tab = selectedTab, model.url(for: tab) != nil {
                    ToolbarItemGroup {
                        Button { model.controller(for: tab)?.webView.goBack() } label: { Image(systemName: "chevron.left") }
                        Button { model.controller(for: tab)?.webView.goForward() } label: { Image(systemName: "chevron.right") }
                        Button { model.controller(for: tab)?.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                        Text(model.urls[tab.id] ?? "").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle).frame(minWidth: 200, maxWidth: 500, alignment: .leading)
                            .textSelection(.enabled)
                        Text("Inspect via Safari > Develop").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        // Load every tab at launch so background tabs deliver notifications and unread counts.
        .onAppear { for tab in allTabs { _ = model.controller(for: tab) } }
    }

    private var selectedTab: TabSpec? { allTabs.first { $0.id == model.selection } }
}

struct BrightspacePrompt: View {
    @EnvironmentObject var model: Model
    @State private var field = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Enter your Brightspace URL (stored for next time)")
            TextField("https://yourschool.brightspace.com", text: $field)
                .textFieldStyle(.roundedBorder).frame(width: 400)
                .onSubmit { model.setBrightspace(field) }
            Button("Open") { model.setBrightspace(field) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Holds every created web view as a subview of one container that never leaves the window;
/// only the selected one is visible, so none reloads or gets detached.
struct WebHost: NSViewRepresentable {
    @EnvironmentObject var model: Model

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        for tab in allTabs {
            guard let wv = model.controller(for: tab)?.webView else { continue }
            if wv.superview !== container {
                wv.frame = container.bounds
                wv.autoresizingMask = [.width, .height]
                container.addSubview(wv)
            }
            wv.isHidden = tab.id != model.selection
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject var model: Model
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.log) { l in
                        Text("\(Self.fmt.string(from: l.time))  \(l.text)")
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled).id(l.id)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            .onChange(of: model.log.count) { _, _ in if let last = model.log.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
    }
}
