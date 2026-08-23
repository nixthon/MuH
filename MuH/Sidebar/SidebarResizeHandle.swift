import SwiftUI
import AppKit

struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat = 150
    let maxWidth: CGFloat = 360
    let defaultWidth: CGFloat = 200
    let theme: AppTheme
    var backgroundOpacity: CGFloat = 1.0

    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 200
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(theme.canvas).opacity(backgroundOpacity))
                .frame(width: DT.Stroke.hairline)

            Rectangle()
                .fill(isDragging ? Color(theme.accent) : (isHovered ? Color(theme.borderStrong) : Color(theme.border).opacity(0.4)))
                .frame(width: DT.Stroke.hairline)

            Rectangle()
                .fill(Color.white.opacity(0.001))
                .frame(width: 8)
                .contentShape(Rectangle())
        }
        .frame(width: DT.Stroke.hairline)
        .onHover { inside in
            isHovered = inside
            if inside {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = width
                        }
                        let newW = max(minWidth, min(maxWidth, dragStartWidth + value.translation.width))
                        width = newW
                    }
                    .onEnded { _ in
                        isDragging = false
                        UserDefaults.standard.set(Double(width), forKey: "muh.sidebar.width")
                    }
            )
            .onTapGesture(count: 2) {
                width = defaultWidth
                UserDefaults.standard.set(Double(defaultWidth), forKey: "muh.sidebar.width")
            }
    }
}
