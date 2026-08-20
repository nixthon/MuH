import AppKit

/// 解析 ghostty 的配置文件 + 引用的主题文件，提取 background / foreground / palette。
enum GhosttyConfigReader {

    struct Colors {
        var background: NSColor?
        var foreground: NSColor?
        var palette: [Int: NSColor] = [:]
    }

    static var configPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Application Support/com.mitchellh.ghostty/config",
            "\(home)/.config/ghostty/config",
        ]
    }

    static var themeSearchPaths: [String] {
        let home = NSHomeDirectory()
        var paths: [String] = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            "\(home)/Library/Application Support/com.mitchellh.ghostty/themes",
            "\(home)/.config/ghostty/themes",
        ]
        if let base = Bundle.main.resourcePath {
            paths.append((base as NSString).appendingPathComponent("ghostty/themes"))
        }
        return paths
    }

    static func load(systemIsDark: Bool) -> Colors {
        var theme = Colors()
        var direct = Colors()

        var mergedKvs: [(String, String)] = []
        for path in configPaths where FileManager.default.fileExists(atPath: path) {
            mergedKvs.append(contentsOf: parseFile(at: path))
            break
        }
        let muhConfigPath = SettingsConfigStore.defaultPath
        if FileManager.default.fileExists(atPath: muhConfigPath) {
            mergedKvs.append(contentsOf: parseFile(at: muhConfigPath))
        }

        if let themeValue = mergedKvs.reversed().first(where: { $0.0 == "theme" })?.1,
           !themeValue.isEmpty {
            let name = resolveThemeNameForAppearance(themeValue, isDark: systemIsDark)
            if let themePath = locateTheme(named: name) {
                let themeKvs = parseFile(at: themePath)
                applyKVs(themeKvs, into: &theme)
            }
        }

        applyKVs(mergedKvs, into: &direct)

        return Colors(
            background: direct.background ?? theme.background,
            foreground: direct.foreground ?? theme.foreground,
            palette: theme.palette.merging(direct.palette) { _, new in new }
        )
    }

    static func resolveThemeNameForAppearance(_ raw: String, isDark: Bool) -> String {
        guard raw.contains(":") && raw.contains(",") else { return raw }
        let wantPrefix = isDark ? "dark:" : "light:"
        for part in raw.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if p.hasPrefix(wantPrefix) {
                return String(p.dropFirst(wantPrefix.count))
            }
        }
        return raw
    }

    static func parseFile(at path: String) -> [(String, String)] {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var result: [(String, String)] = []
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            result.append((key, value))
        }
        return result
    }

    private static func applyKVs(_ kvs: [(String, String)], into colors: inout Colors) {
        for (key, value) in kvs {
            switch key {
            case "background":
                if let c = parseColor(value) { colors.background = c }
            case "foreground":
                if let c = parseColor(value) { colors.foreground = c }
            case "palette":
                if let eq = value.firstIndex(of: "="),
                   let idx = Int(value[..<eq]),
                   let c = parseColor(String(value[value.index(after: eq)...])) {
                    colors.palette[idx] = c
                }
            default: break
            }
        }
    }

    static func resolvedThemePath() -> String? {
        let sources: [String] = [SettingsConfigStore.defaultPath] + configPaths
        for path in sources where FileManager.default.fileExists(atPath: path) {
            let kvs = parseFile(at: path)
            guard let themeValue = kvs.first(where: { $0.0 == "theme" })?.1,
                  !themeValue.isEmpty else { continue }
            let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let name = resolveThemeNameForAppearance(themeValue, isDark: isDark)
            return locateTheme(named: name)
        }
        return nil
    }

    static func locateTheme(named name: String) -> String? {
        for dir in themeSearchPaths {
            let path = "\(dir)/\(name)"
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    static func parseColor(_ raw: String) -> NSColor? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s = String(s.dropFirst()) }
        if s.hasPrefix("rgb:") {
            let body = String(s.dropFirst(4))
            let parts = body.components(separatedBy: "/")
            guard parts.count == 3,
                  let r = UInt8(parts[0], radix: 16),
                  let g = UInt8(parts[1], radix: 16),
                  let b = UInt8(parts[2], radix: 16) else { return nil }
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        }
        if s.count == 3 {
            let chars = Array(s)
            let dup = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
            return parseColor("#" + dup)
        }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xff) / 255
        let g = CGFloat((value >> 8)  & 0xff) / 255
        let b = CGFloat( value        & 0xff) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
