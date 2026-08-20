import SwiftUI

struct IconButton<Label: View>: View {
    let theme: AppTheme
    var help: String?
    var size: CGFloat = 24
    var cornerRadius: CGFloat = 4
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isHovered ? Color(theme.border) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }
}
