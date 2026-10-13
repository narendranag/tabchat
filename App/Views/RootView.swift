import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAdd = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(showingAdd: $showingAdd)
                .frame(width: 56)
            Divider()
            ZStack(alignment: .top) {
                WebHost()
                if let controller = model.selectedController {
                    TabOverlay(controller: controller)
                } else {
                    EmptyStateView(showingAdd: $showingAdd)
                }
            }
            .overlay(alignment: .bottom) { ToastView() }
        }
        .navigationTitle(model.selectedTab?.displayName ?? "Tabchat")
        .toolbar { NavigationToolbar() }
        .sheet(isPresented: $showingAdd) { AddServiceSheet() }
        .onAppear { model.start() }
    }
}

/// Error screen and find bar for the selected tab, drawn above the web views.
private struct TabOverlay: View {
    let controller: TabController

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let error = controller.loadError {
                ErrorOverlay(message: error) { controller.retry() }
            }
            if controller.findVisible {
                FindBar(controller: controller)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .allowsHitTesting(controller.loadError != nil || controller.findVisible)
    }
}

private struct EmptyStateView: View {
    @Binding var showingAdd: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text("No services yet").font(.title2)
            Button("Add a service") { showingAdd = true }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct ErrorOverlay: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("Can't load this page").font(.title3)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button("Retry", action: retry).keyboardShortcut(.defaultAction)
            Text("Retrying automatically every 10 seconds.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

private struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let text = model.toast {
            Text(text)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 16)
                .transition(.opacity)
        }
    }
}

private struct NavigationToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            let controller = model.selectedController
            Button { controller?.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!(controller?.canGoBack ?? false))
                .help("Back")
            Button { controller?.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!(controller?.canGoForward ?? false))
                .help("Forward")
            Button { controller?.reload() } label: { Image(systemName: "arrow.clockwise") }
                .disabled(controller == nil)
                .help("Reload")
            Button { controller?.goHome() } label: { Image(systemName: "house") }
                .disabled(controller == nil)
                .help("Home")
        }
    }
}
