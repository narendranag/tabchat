import SwiftUI

struct AppCommands: Commands {
    let model: AppModel
    @ObservedObject var menu: MenuState

    var body: some Commands {
        // Close Window (Cmd+W) is the standard item; the main window's delegate turns it into a hide.
        CommandGroup(replacing: .newItem) {
            Button("New Service…") {
                MainWindow.shared.show()
                model.showingAdd = true
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("Reopen Closed Service") { model.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(model.closedTabs.isEmpty)
        }

        CommandGroup(before: .toolbar) {
            Button("Reload") { model.selectedController?.reload() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Home") { model.selectedController?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Back") { model.selectedController?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { model.selectedController?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()
            Button("Find…") { model.selectedController?.showFind() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find Next") { model.selectedController?.find() }
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { model.selectedController?.find(backwards: true) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Split View") { model.toggleSplit() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Quick Switcher…") { model.showPalette() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
        }

        CommandMenu("Services") {
            ForEach(Array(menu.items.enumerated()), id: \.element.id) { index, item in
                if index < 9 {
                    Button(item.name) { model.select(index: index) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                } else {
                    Button(item.name) { model.select(index: index) }
                }
            }
            Divider()
            Button("Next Service") { model.selectRelative(1) }
                .keyboardShortcut(.tab, modifiers: .control)
            Button("Previous Service") { model.selectRelative(-1) }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
            Button("Show Next Service") { model.selectRelative(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Show Previous Service") { model.selectRelative(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
