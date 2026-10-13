import SwiftUI

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}

        CommandGroup(after: .textEditing) {
            Button("Find…") { model.selectedController?.showFind() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find Next") { model.selectedController?.find() }
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { model.selectedController?.find(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandMenu("Navigation") {
            Button("Back") { model.selectedController?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { model.selectedController?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Reload") { model.selectedController?.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Home") { model.selectedController?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }

        CommandMenu("Tabs") {
            ForEach(Array(model.tabs.prefix(9).enumerated()), id: \.element.id) { index, tab in
                Button(tab.displayName) { model.select(index: index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
    }
}
