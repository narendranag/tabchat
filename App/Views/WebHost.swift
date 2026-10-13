import SwiftUI
import WebKit

/// Holds every tab's web view as a subview of one container that stays in the window. Only the
/// selected view is visible, so switching tabs never reloads a page or detaches a web view.
struct WebHost: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ container: NSView, context: Context) {
        for tab in model.tabs {
            guard let webView = model.controllers[tab.id]?.webView else { continue }
            if webView.superview !== container {
                webView.frame = container.bounds
                webView.autoresizingMask = [.width, .height]
                container.addSubview(webView)
            }
            webView.isHidden = tab.id != model.selection
        }
    }
}
