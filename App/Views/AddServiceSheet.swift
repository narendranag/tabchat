import SwiftUI

struct AddServiceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Service?
    @State private var name = ""
    @State private var address = ""

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(picked.map { "Add \($0.name)" } ?? "Add a service").font(.title3.bold())
            if let service = picked {
                form(for: service)
            } else {
                catalog
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

    private var catalog: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ServiceCatalog.all + [ServiceCatalog.custom]) { service in
                Button { choose(service) } label: {
                    VStack(spacing: 6) {
                        LetterTile(name: service.name, colorHex: Self.color(for: service), size: 44)
                        Text(service.kind == .custom ? "Custom website" : service.name)
                            .font(.callout).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity).padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func form(for service: Service) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if service.kind == .custom {
                TextField("Name", text: $name)
            }
            TextField(service.kind == .custom ? "Address (example.com)" : "https://yourschool.brightspace.com", text: $address)
                .onSubmit { submit(service) }
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
            model.addTab(service: service)
            dismiss()
        }
    }

    private func submit(_ service: Service) {
        guard let url = URLInput.normalize(address), service.kind != .custom || !name.isEmpty else { return }
        model.addTab(service: service, name: service.kind == .custom ? name : nil, url: url.absoluteString)
        dismiss()
    }

    private static func color(for service: Service) -> String {
        let index = ServiceCatalog.all.firstIndex(of: service) ?? TabPalette.colors.count - 1
        return TabPalette.colors[index % TabPalette.colors.count]
    }
}
