import CoreGraphics
import Foundation

/// Two tabs shown side by side. `focus` says which side a sidebar click replaces and which tab the
/// toolbar and shortcuts act on; `AppState.selectedTabId` always mirrors the focused tab.
struct SplitState: Codable, Equatable, Sendable {
    enum Side: String, Codable, Sendable {
        case left
        case right
    }

    var left: UUID
    var right: UUID
    var focus = Side.left

    var focusedId: UUID {
        focus == .left ? left : right
    }

    var ids: [UUID] {
        [left, right]
    }

    func contains(_ id: UUID) -> Bool {
        left == id || right == id
    }

    func partner(of id: UUID) -> UUID {
        id == left ? right : left
    }

    /// A tab already on screen just takes the focus; any other tab replaces the focused side.
    mutating func select(_ id: UUID) {
        if id == left {
            focus = .left
        } else if id == right {
            focus = .right
        } else if focus == .left {
            left = id
        } else {
            right = id
        }
    }

    /// Puts `id` on the side that is not focused, then focuses it ("Open in Split View").
    mutating func place(_ id: UUID) {
        guard !contains(id) else {
            select(id)
            return
        }
        if focus == .left {
            right = id
            focus = .right
        } else {
            left = id
            focus = .left
        }
    }
}

/// The geometry of the two panes. Pure, so the clamping and drag maths can be tested.
enum SplitMath {
    static let minRatio = 0.2
    static let maxRatio = 0.8
    static let defaultRatio = 0.5
    /// Space between the panes; the draggable divider lives here.
    static let gutter: CGFloat = 8

    static func clamp(_ ratio: Double) -> Double {
        ratio.isFinite ? min(max(ratio, minRatio), maxRatio) : defaultRatio
    }

    /// Widths of the left and right pane for a container `total` wide.
    static func widths(total: CGFloat, ratio: Double) -> (left: CGFloat, right: CGFloat) {
        let usable = max(0, total - gutter)
        let left = (usable * clamp(ratio)).rounded()
        return (left, usable - left)
    }

    /// The ratio for a divider dragged so its centre sits at `dragX`.
    static func ratio(dragX: CGFloat, total: CGFloat) -> Double {
        let usable = total - gutter
        guard usable > 0 else { return defaultRatio }
        return clamp(Double((dragX - gutter / 2) / usable))
    }
}
