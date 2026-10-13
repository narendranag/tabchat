import SwiftUI

/// Drawn over the two panes: the outline of the focused side and the draggable divider with its
/// close button. The error screen and find bar of each pane live here too, kept inside their pane.
struct PaneOverlays: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if let split = model.split {
                let widths = SplitMath.widths(total: size.width, ratio: model.splitRatio)
                let rightX = widths.left + SplitMath.gutter
                pane(split.left, offsetX: 0, width: widths.left, height: size.height)
                pane(split.right, offsetX: rightX, width: widths.right, height: size.height)
                focusOutline(
                    split.focus == .left ? 0 : rightX,
                    width: split.focus == .left ? widths.left : widths.right,
                    height: size.height
                )
                SplitDivider(offsetX: widths.left, total: size.width, height: size.height)
            } else if let id = model.selection {
                pane(id, offsetX: 0, width: size.width, height: size.height)
            }
        }
    }

    @ViewBuilder
    private func pane(_ id: UUID, offsetX: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        if let controller = model.controllers[id] {
            TabOverlay(controller: controller)
                .frame(width: width, height: height)
                .offset(x: offsetX)
        }
    }

    private func focusOutline(_ offsetX: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 2)
            .frame(width: width, height: height)
            .offset(x: offsetX)
            .allowsHitTesting(false)
    }
}

private struct SplitDivider: View {
    @Environment(AppModel.self) private var model
    /// Left edge of the gutter.
    let offsetX: CGFloat
    let total: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.separator).frame(width: 2)
            Button { model.closeSplit() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(.separator))
            }
            .buttonStyle(.plain)
            .help("Close split view")
            .padding(.top, 10)
        }
        .frame(width: SplitMath.gutter, height: height)
        .background(Color(nsColor: .underPageBackgroundColor))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("panes"))
                .onChanged { model.setSplitRatio(SplitMath.ratio(dragX: $0.location.x, total: total), commit: false) }
                .onEnded { model.setSplitRatio(SplitMath.ratio(dragX: $0.location.x, total: total), commit: true) }
        )
        .offset(x: offsetX)
    }
}
