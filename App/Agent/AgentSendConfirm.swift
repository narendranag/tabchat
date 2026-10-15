import AppKit
import SwiftUI

/// What an agent's `send` asks the owner to confirm.
struct AgentSendRequest: Equatable, Sendable {
    var service: String
    var chat: String
    var text: String
    var client: String
}

/// Tabchat's own confirmation for an agent's `send`: a sheet on the main window showing who asks, the
/// recipient and the whole message. Only a click on Send (or Cmd+Return) sends; plain Return does not,
/// so typing in another app while the sheet appears cannot send by accident. Unanswered, it cancels
/// itself after `timeout`.
@MainActor
enum AgentSendConfirm {
    static let timeout: TimeInterval = 300

    static func ask(_ request: AgentSendRequest) async -> Bool {
        guard let parent = MainWindow.shared.window, MainWindow.shared.show(), parent.attachedSheet == nil else {
            return false
        }
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let deadline = Date().addingTimeInterval(timeout)
        sheet.contentViewController = NSHostingController(rootView: AgentSendSheet(request: request, deadline: deadline) {
            parent.endSheet(sheet, returnCode: $0 ? .OK : .cancel)
        })
        return await withCheckedContinuation { continuation in
            parent.beginSheet(sheet) { continuation.resume(returning: $0 == .OK) }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if parent.attachedSheet === sheet {
                    parent.endSheet(sheet, returnCode: .cancel)
                }
            }
        }
    }
}

struct AgentSendSheet: View {
    let request: AgentSendRequest
    let deadline: Date
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "paperplane.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white, Self.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Send on \(request.service)?").font(.title3.weight(.semibold))
                    Text("\(request.client) asks to send this message from your account.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text("To").foregroundStyle(.secondary)
                Text(request.chat).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            }
            .font(.body)
            ScrollView {
                HStack {
                    Spacer(minLength: 48)
                    Text(request.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Self.bubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(12)
            }
            .frame(minHeight: 70, maxHeight: 240)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(deadline.timeIntervalSince(context.date)))
                    let clock = "\(left / 60):\(String(format: "%02d", left % 60))"
                    Text("\(request.text.count) characters · cancels by itself in \(clock)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button("Cancel", role: .cancel) { answer(false) }
                    .keyboardShortcut(.cancelAction)
                Button {
                    answer(true)
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .tint(Self.accent)
                .help("Send (⌘↩)")
            }
            Text("Nothing is sent unless you click Send. Return alone does nothing here.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 440)
    }

    /// WhatsApp's green, and its outgoing bubble in light and dark.
    private static let accent = Color(red: 0.15, green: 0.83, blue: 0.40)
    private static let bubble = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.0, green: 0.36, blue: 0.29, alpha: 1)
            : NSColor(red: 0.85, green: 0.99, blue: 0.83, alpha: 1)
    })
}
