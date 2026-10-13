import SwiftUI
import UserNotifications

@main
struct TabchatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        // A single Window (not WindowGroup) so Cmd+N cannot open a second copy of every tab.
        Window("Tabchat", id: "main") {
            if AppEnvironment.isTesting {
                Color.clear
            } else {
                RootView()
                    .environment(model)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .commands { AppCommands(model: model) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isTesting else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Closing the window keeps the app (and every tab's connection) alive.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = (response.notification.request.content.userInfo["tab"] as? String).flatMap(UUID.init)
        completionHandler()
        guard let id else { return }
        Task { @MainActor in AppModel.shared.reveal(id) }
    }
}
