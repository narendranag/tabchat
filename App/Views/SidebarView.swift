import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var showingAdd: Bool
    @State private var renaming: Tab?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.tabs) { tab in
                        SidebarItem(tab: tab, renaming: $renaming)
                    }
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            Button { showingAdd = true } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .help("Add service")
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .sheet(item: $renaming) { RenameSheet(tab: $0) }
    }
}

private struct SidebarItem: View {
    @Environment(AppModel.self) private var model
    let tab: Tab
    @Binding var renaming: Tab?

    var body: some View {
        let selected = model.selection == tab.id
        let inSplit = model.split?.contains(tab.id) ?? false
        let asleep = model.sleeping.contains(tab.id)
        ZStack(alignment: .topTrailing) {
            ServiceIcon(tab: tab, size: 36)
                .padding(4)
                .opacity(asleep ? 0.45 : 1)
                .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(selected ? Color.accentColor : (inSplit ? Color.accentColor.opacity(0.4) : .clear), lineWidth: 2)
                )
                .overlay(alignment: .bottomTrailing) {
                    if asleep {
                        Image(systemName: "moon.zzz.fill").font(.system(size: 10)).foregroundStyle(.secondary).padding(2)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if tab.incognito {
                        Image(systemName: "eye.slash.fill").font(.system(size: 10)).foregroundStyle(.secondary).padding(2)
                    }
                }
            if let unread = model.unread[tab.id], unread.hasUnread {
                if unread.count >= 1 {
                    Text(unread.count > 99 ? "99+" : "\(unread.count)")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(.red))
                        .offset(x: 4, y: -2)
                } else {
                    Circle().fill(.red).frame(width: 10, height: 10).offset(x: 2, y: 0)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(tab.id) }
        .help(tab.displayName + (tab.incognito ? " (incognito)" : "") + (asleep ? " (asleep)" : ""))
        .draggable(tab.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init) else { return false }
            model.move(dragged, before: tab.id)
            return true
        }
        .contextMenu {
            Button("Rename…") { renaming = tab }
            Button("Reload") { model.controllers[tab.id]?.reload() }
            Button("Add Another Account") { model.addAnotherAccount(of: tab) }
            Button("Duplicate") { model.duplicate(tab.id) }
            Button("Open in Split View") { model.openSplit(with: tab.id) }
                .disabled(model.tabs.count < 2)
            Divider()
            if !tab.isEphemeral {
                Toggle("Allow Sleep", isOn: Binding(get: { tab.allowSleep }, set: { model.setAllowSleep(tab.id, $0) }))
                Button("Sleep Now") { model.sleepNow(tab.id) }
                    .disabled(!model.canSleepNow(tab.id))
            }
            Toggle("Mute Notifications", isOn: Binding(get: { tab.muted }, set: { model.setMuted(tab.id, $0) }))
            Divider()
            Button("Remove", role: .destructive) { model.removeTab(tab.id) }
        }
    }
}

/// The site's own icon once fetched; until then (or if none loads) a coloured letter tile.
struct ServiceIcon: View {
    @Environment(AppModel.self) private var model
    let tab: Tab
    let size: CGFloat

    var body: some View {
        if let icon = model.icons[tab.iconKey] {
            Image(nsImage: icon)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            LetterTile(name: tab.displayName, colorHex: tab.colorHex, size: size)
        }
    }
}

struct LetterTile: View {
    let name: String
    let colorHex: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.first.map { Character($0.uppercased()) } ?? "?"))
                    .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
            )
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0x808080
        self.init(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct RenameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let tab: Tab
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename tab").font(.headline)
            TextField("Name", text: $name)
                .frame(width: 280)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .onAppear { name = tab.displayName }
    }

    private func save() {
        model.rename(tab.id, to: name)
        dismiss()
    }
}
