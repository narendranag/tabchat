import SwiftUI

struct AddServiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Service?
    @State private var name = ""
    @State private var address = ""
    @State private var editing = false
    @State private var incognito = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(picked.map { "Add \($0.name)" } ?? "Add a service").font(.title3.bold())
                Spacer()
                if picked == nil {
                    Button(editing ? "Done" : "Edit") { editing.toggle() }
                        .help("Hide services you don't use and drag cards into your own order")
                }
            }
            if let service = picked {
                form(for: service)
            } else {
                catalog
                if editing {
                    Text("Drag cards to reorder. Click the eye to hide a service you don't use.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    incognitoToggle
                }
            }
            HStack {
                if picked != nil {
                    Button("Back") { picked = nil }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var incognitoToggle: some View {
        Toggle("Open once in incognito", isOn: $incognito)
            .help("A tab with no saved sign-in or history; it is gone when you quit Tabchat")
    }

    private var catalog: some View {
        let settings = model.state.settings
        let cards = CatalogLayout.visible(
            ServiceCatalog.all, order: settings.serviceOrder, hidden: settings.hiddenServices, editing: editing
        )
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(cards + [ServiceCatalog.custom]) { service in
                card(service, hidden: settings.hiddenServices.contains(service.id))
            }
        }
    }

    @ViewBuilder
    private func card(_ service: Service, hidden: Bool) -> some View {
        let movable = editing && service.kind != .custom
        Button {
            if !editing {
                choose(service)
            }
        } label: {
            VStack(spacing: 6) {
                LetterTile(name: service.name, colorHex: Self.color(for: service), size: 44)
                Text(service.kind == .custom ? "Custom website" : service.name)
                    .font(.callout).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .opacity(hidden ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if movable {
                Button { model.toggleServiceHidden(service.id) } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye").padding(4)
                }
                .buttonStyle(.plain)
                .help(hidden ? "Show this service" : "Hide this service")
            }
        }
        .modifier(CardDrag(enabled: movable, id: service.id) { dragged in
            model.moveService(dragged, before: service.id)
        })
    }

    private func form(for service: Service) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if service.kind == .custom {
                TextField("Name", text: $name)
            }
            TextField(service.kind == .custom ? "Address (example.com)" : "https://yourschool.brightspace.com", text: $address)
                .onSubmit { submit(service) }
            incognitoToggle
            HStack {
                Spacer()
                Button("Add") { submit(service) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(URLInput.normalize(address) == nil || (service.kind == .custom && name.isEmpty))
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func choose(_ service: Service) {
        if service.asksForURL {
            picked = service
        } else {
            model.addTab(service: service, name: incognito ? Self.incognitoName(service.name) : nil, incognito: incognito)
            dismiss()
        }
    }

    private func submit(_ service: Service) {
        guard let url = URLInput.normalize(address), service.kind != .custom || !name.isEmpty else { return }
        let label = service.kind == .custom ? name : nil
        model.addTab(
            service: service, name: incognito ? Self.incognitoName(label ?? service.name) : label,
            url: url.absoluteString, incognito: incognito
        )
        dismiss()
    }

    private static func incognitoName(_ name: String) -> String {
        "\(name) (incognito)"
    }

    private static func color(for service: Service) -> String {
        let index = ServiceCatalog.all.firstIndex(of: service) ?? TabPalette.colors.count - 1
        return TabPalette.colors[index % TabPalette.colors.count]
    }
}

/// Makes a card draggable onto other cards while the sheet is in Edit mode.
private struct CardDrag: ViewModifier {
    let enabled: Bool
    let id: String
    let onDrop: (String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(id)
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first else { return false }
                    onDrop(dragged)
                    return true
                }
        } else {
            content
        }
    }
}
