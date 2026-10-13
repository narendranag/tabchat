import SwiftUI

struct FindBar: View {
    @Bindable var controller: TabController
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("Find on page", text: $controller.findText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .focused($focused)
                .onSubmit { controller.find() }
                .onChange(of: controller.findText) { controller.find() }
            if controller.findMissed {
                Text("Not found").font(.caption).foregroundStyle(.secondary)
            }
            Button { controller.find(backwards: true) } label: { Image(systemName: "chevron.up") }
                .help("Previous")
            Button { controller.find() } label: { Image(systemName: "chevron.down") }
                .help("Next")
            Button { controller.hideFind() } label: { Image(systemName: "xmark") }
                .help("Close")
        }
        .buttonStyle(.borderless)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3)
        .onExitCommand { controller.hideFind() }
        .onAppear { focused = true }
    }
}
