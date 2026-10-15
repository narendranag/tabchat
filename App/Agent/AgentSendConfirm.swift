import AppKit

/// Tabchat's own confirmation for an agent's `send`: a sheet on the main window showing the recipient
/// and the whole message. Only a click on Send (or Cmd+Return) sends; plain Return does not, so typing
/// in another app while the sheet appears cannot send by accident. Unanswered, it cancels itself.
@MainActor
enum AgentSendConfirm {
    static let timeout: Duration = .seconds(300)

    static func ask(chat: String, text: String, client: String) async -> Bool {
        guard let window = MainWindow.shared.window, MainWindow.shared.show(), window.attachedSheet == nil else {
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Send this message to \(chat)?"
        alert.informativeText = "\(client) asks to send it from your WhatsApp. Nothing is sent unless you click Send."
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 380, height: 150)
        if let view = scroll.documentView as? NSTextView {
            view.string = text
            view.isEditable = false
            view.font = .systemFont(ofSize: NSFont.systemFontSize)
        }
        alert.accessoryView = scroll
        let send = alert.addButton(withTitle: "Send")
        send.keyEquivalent = "\r"
        send.keyEquivalentModifierMask = .command
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1b}"
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if window.attachedSheet === alert.window {
                    window.endSheet(alert.window, returnCode: .cancel)
                }
            }
        }
    }
}
