import SwiftUI
import WebKit

/// Holds every tab's web view as a subview of one container that stays in the window. Only the
/// visible views are shown (one, or two side by side in split view), so switching tabs never
/// reloads a page or detaches a web view; a sleeping tab simply has no web view in here.
struct WebHost: NSViewRepresentable {
    @Environment(AppModel.self) private var model

    func makeNSView(context: Context) -> SplitContainer {
        let container = SplitContainer()
        container.onFocus = { [model] side in model.focusSplit(side) }
        return container
    }

    func updateNSView(_ container: SplitContainer, context: Context) {
        let ids = model.split?.ids ?? model.selection.map { [$0] } ?? []
        for tab in model.tabs {
            guard let webView = model.controllers[tab.id]?.webView else { continue }
            if webView.superview !== container {
                webView.frame = container.bounds
                container.addSubview(webView)
            }
            webView.isHidden = !ids.contains(tab.id)
        }
        container.panes = ids.compactMap { model.controllers[$0]?.webView }
        container.ratio = model.splitRatio
        container.needsLayout = true
    }
}

/// Lays out the visible web views: one fills the container, two share it with a gutter between
/// (drawn and dragged by `SplitOverlay`). A click inside a pane reports which side was clicked.
@MainActor
final class SplitContainer: NSView {
    var panes: [NSView] = []
    var ratio = SplitMath.defaultRatio
    var onFocus: (@MainActor (SplitState.Side) -> Void)?
    private var monitor: Any?

    override func layout() {
        super.layout()
        for view in subviews {
            view.frame = bounds
        }
        guard panes.count == 2 else { return }
        let widths = SplitMath.widths(total: bounds.width, ratio: ratio)
        panes[0].frame = NSRect(x: 0, y: 0, width: widths.left, height: bounds.height)
        panes[1].frame = NSRect(x: widths.left + SplitMath.gutter, y: 0, width: widths.right, height: bounds.height)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick(event) }
            return event
        }
    }

    /// Reports the pane under the click without consuming it, so the page still gets the click.
    private func handleClick(_ event: NSEvent) {
        guard panes.count == 2, event.window === window else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if point.x < panes[0].frame.maxX {
            onFocus?(.left)
        } else if point.x >= panes[1].frame.minX {
            onFocus?(.right)
        }
    }
}
