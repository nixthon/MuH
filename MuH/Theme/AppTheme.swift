import AppKit

/// 多层调色板。从 ghostty 配置派生或提供系统外观 fallback。
struct AppTheme: Equatable {
    let isDark: Bool

    // Surfaces
    let canvas: NSColor          // 画布主背景 = ghostty.background
    let surface: NSColor         // 终端窗口背景 = ghostty.background
    let sidebar: NSColor         // 侧边栏背景

    // Borders
    let border: NSColor          // hairline / hover / 选中态
    let borderStrong: NSColor    // 区段分隔

    // Text
    let textPrimary: NSColor     // = ghostty.foreground
    let textSecondary: NSColor
    let textTertiary: NSColor

    // Accent
    let accent: NSColor
    let accentMuted: NSColor

    // Status
    let success: NSColor         // 完成 / 存活空闲（绿色）
    let danger: NSColor          // 阻塞/错误（红色）
}

extension AppTheme {
    static func derive(
        background: NSColor?,
        foreground: NSColor?,
        accent: NSColor?,
        systemIsDark: Bool
    ) -> AppTheme {
        let bg = background ?? (systemIsDark
            ? NSColor(srgbRed: 0.07, green: 0.07, blue: 0.075, alpha: 1)
            : NSColor(srgbRed: 0.985, green: 0.982, blue: 0.978, alpha: 1))

        let fg = foreground ?? (systemIsDark
            ? NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.10, blue: 0.105, alpha: 1))

        let bgBrightness = bg.usingColorSpace(.sRGB)?.brightnessComponent ?? 0
        let isDark = bgBrightness < 0.5

        let sidebar = bg.mixed(with: fg, fraction: isDark ? 0.04 : 0.05) ?? bg
        let border = bg.mixed(with: fg, fraction: 0.12) ?? bg
        let borderStrong = bg.mixed(with: fg, fraction: 0.22) ?? bg

        let textSecondary = fg.mixed(with: bg, fraction: 0.40) ?? fg
        let textTertiary = fg.mixed(with: bg, fraction: 0.65) ?? fg

        let accentColor = accent ?? (isDark
            ? NSColor(srgbRed: 0.953, green: 0.659, blue: 0.196, alpha: 1)
            : NSColor(srgbRed: 0.850, green: 0.450, blue: 0.050, alpha: 1))
        let accentMuted = accentColor.withAlphaComponent(0.10)

        let success = isDark
            ? NSColor(srgbRed: 0.247, green: 0.729, blue: 0.314, alpha: 1)  // #3FBA50
            : NSColor(srgbRed: 0.180, green: 0.600, blue: 0.235, alpha: 1)
        let danger = isDark
            ? NSColor(srgbRed: 0.973, green: 0.318, blue: 0.286, alpha: 1)  // #F85149
            : NSColor(srgbRed: 0.827, green: 0.184, blue: 0.184, alpha: 1)

        return AppTheme(
            isDark: isDark,
            canvas: bg,
            surface: bg,
            sidebar: sidebar,
            border: border,
            borderStrong: borderStrong,
            textPrimary: fg,
            textSecondary: textSecondary,
            textTertiary: textTertiary,
            accent: accentColor,
            accentMuted: accentMuted,
            success: success,
            danger: danger
        )
    }

    static func systemFallback(isDark: Bool) -> AppTheme {
        derive(background: nil, foreground: nil, accent: nil, systemIsDark: isDark)
    }
}

extension NSColor {
    func mixed(with other: NSColor, fraction: CGFloat) -> NSColor? {
        guard let a = self.usingColorSpace(.sRGB),
              let b = other.usingColorSpace(.sRGB) else { return nil }
        let f = max(0, min(1, fraction))
        return NSColor(
            srgbRed: a.redComponent   * (1 - f) + b.redComponent   * f,
            green:   a.greenComponent * (1 - f) + b.greenComponent * f,
            blue:    a.blueComponent  * (1 - f) + b.blueComponent  * f,
            alpha:   a.alphaComponent * (1 - f) + b.alphaComponent * f
        )
    }
}
