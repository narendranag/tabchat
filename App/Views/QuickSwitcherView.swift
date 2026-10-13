import SwiftUI

/// The Cmd+K palette: a search field over a filtered list of tabs and actions, centred over the window.
struct QuickSwitcherView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var index = 0
    @State private var monitor: Any?
    @FocusState private var focused: Bool

    private var results: [PaletteItem] {
        PaletteRanker.rank(model.paletteItems(), query: query)
    }

    var body: some View {
        let results = results
        ZStack {
            Color.black.opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture { model.showingPalette = false }
            VStack(spacing: 0) {
                TextField("Go to a service or run an action", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding(12)
                    .focused($focused)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { position, item in
                                row(item, highlighted: position == index)
                                    .id(item.id)
                                    .onTapGesture { model.run(item) }
                            }
                            if results.isEmpty {
                                Text("No matches").foregroundStyle(.secondary).padding(12)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: index) { _, new in
                        if results.indices.contains(new) {
                            proxy.scrollTo(results[new].id)
                        }
                    }
                }
            }
            .frame(width: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
            .shadow(radius: 12)
            .offset(y: -40)
        }
        .onChange(of: query) { index = 0 }
        .onAppear {
            focused = true
            install()
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            // Hand the keyboard back to the page that was showing.
            Task { @MainActor [model] in
                if let webView = model.selectedController?.webView {
                    webView.window?.makeFirstResponder(webView)
                }
            }
        }
    }

    private func row(_ item: PaletteItem, highlighted: Bool) -> some View {
        HStack(spacing: 10) {
            switch item.target {
            case let .tab(id):
                if let tab = model.tabs.first(where: { $0.id == id }) {
                    ServiceIcon(tab: tab, size: 22)
                }
            case .action:
                Image(systemName: "command").frame(width: 22, height: 22).foregroundStyle(.secondary)
            }
            Text(item.title).lineLimit(1)
            if item.sleeping {
                Image(systemName: "moon.zzz.fill").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.unread > 0 {
                Text(item.unread > 99 ? "99+" : "\(item.unread)")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.red))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(highlighted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    /// Arrow keys, Return and Esc are taken before the text field sees them.
    private func install() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
            let code = event.keyCode
            let consumed = MainActor.assumeIsolated {
                let results = PaletteRanker.rank(model.paletteItems(), query: query)
                switch code {
                case 125:
                    index = PaletteRanker.move(index, by: 1, count: results.count)
                case 126:
                    index = PaletteRanker.move(index, by: -1, count: results.count)
                case 36, 76:
                    if results.indices.contains(index) {
                        model.run(results[index])
                    }
                case 53:
                    model.showingPalette = false
                default:
                    return false
                }
                return true
            }
            return consumed ? nil : event
        }
    }
}
