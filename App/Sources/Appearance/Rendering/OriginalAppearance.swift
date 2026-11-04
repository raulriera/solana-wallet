import Foundation
import Themes

/// The built-in theme with the system's colors.
nonisolated enum OriginalAppearance {
    // swift-format-ignore: NeverForceUnwrap
    static let id = UUID(uuidString: "6833C0F7-9A25-47E8-8FA7-1694A40312B3")!
    static let packageURL = Bundle.main.url(forResource: "Original", withExtension: "xtheme", subdirectory: "Themes.bundle")
    static let palette = Palette(
        background: .system(.systemGroupedBackground), surface: .system(.secondarySystemGroupedBackground),
        text: .system(.label), secondaryText: .system(.secondaryLabel), separator: .system(.separator),
        primary: .system(.systemBlue), onPrimary: .system(.white),
        secondary: .system(.tertiarySystemFill), onSecondary: .system(.systemBlue),
        destructive: .system(.systemRed), onDestructive: .system(.white)
    )
    static let colors = Colors(light: palette, dark: palette,
                               lightIncreasedContrast: palette, darkIncreasedContrast: palette)
}
