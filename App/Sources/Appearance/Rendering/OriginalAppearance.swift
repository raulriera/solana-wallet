import Foundation
import Themes

/// The built-in theme with the system's colors.
nonisolated enum OriginalAppearance {
    // swift-format-ignore: NeverForceUnwrap
    static let id = UUID(uuidString: "6833C0F7-9A25-47E8-8FA7-1694A40312B3")!
    static let palette = Palette { role in
        switch role {
        case .background: .system(.systemGroupedBackground)
        case .surface: .system(.secondarySystemGroupedBackground)
        case .separator: .system(.separator)
        case .primary: .system(.systemBlue)
        case .onPrimary: .system(.white)
        case .secondary: .system(.tertiarySystemFill)
        case .onSecondary: .system(.label)
        case .destructive: .system(.systemRed)
        case .onDestructive: .system(.white)
        case .border: .system(.clear)
        case .sidebar: .system(.clear)
        }
    }
    static let tokens = Tokens(colors: Colors(light: palette, dark: palette), fontDesign: .default)
}
