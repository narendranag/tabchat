import AppKit
import SwiftUI

/// Makes the red button and Cmd+W hide the main window instead of closing it.
///
/// A hidden window keeps its web views attached, so pages keep running at full speed and keep
/// delivering notifications and unread counts; a closed window would detach them and WebKit would
/// throttle them. SwiftUI owns the window and sets its own delegate, so this object replaces that
/// delegate, answers `windowShouldClose` itself (orderOut, return false), and forwards every
/// other delegate message to SwiftUI's original delegate. Popups, Settings and sheets are other
/// windows and close normally.
@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()

    private(set) weak var window: NSWindow?
    private nonisolated(unsafe) weak var original: NSWindowDelegate?
    private var appliedLaunchVisibility = false

    /// Called once the SwiftUI view is in its window.
    func adopt(_ window: NSWindow, startHidden: Bool) {
        if self.window !== window {
            self.window = window
            if window.delegate !== self {
                original = window.delegate
                window.delegate = self
            }
        }
        if !appliedLaunchVisibility {
            appliedLaunchVisibility = true
            // Honoured at every launch, not only a login launch: macOS does not tell us which it was.
            if startHidden {
                window.orderOut(nil)
            }
        }
    }

    /// Shows the window and focuses the app. False when there is no window yet.
    @discardableResult
    func show() -> Bool {
        NSApp.unhide(nil)
        NSApp.activate()
        guard let window else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        original
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }
}

/// Reports the hosting `NSWindow` of the view it is placed behind.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HookView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class HookView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}
