import AppKit

enum DT {
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let row: CGFloat = 6
        static let card: CGFloat = 10
        static let modal: CGFloat = 12
        static let pill: CGFloat = 4
        static let strip: CGFloat = 6
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 200
        static let rowHeight: CGFloat = 44
        static let tabHeight: CGFloat = 32
        static let pillInset: CGFloat = 4
        static let tabItemWidth: CGFloat = 140
        static let trafficLightTopInset: CGFloat = 34
    }

    enum Stroke {
        static let hairline: CGFloat = 1.0 / (NSScreen.main?.backingScaleFactor ?? 2.0)
    }

    enum Font {
        static let body: NSFont = NSFont.systemFont(ofSize: 13, weight: .medium)
        static let bodyBold: NSFont = NSFont.systemFont(ofSize: 13, weight: .bold)
        static let small: NSFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let mono: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        static let micro: NSFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    }
}
