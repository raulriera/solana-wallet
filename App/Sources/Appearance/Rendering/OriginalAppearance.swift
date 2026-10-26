import Foundation
import Themes

/// The original system appearance and the complete baseline used by exported templates.
nonisolated enum OriginalAppearance {
    // swift-format-ignore: NeverForceUnwrap
    static let id = UUID(uuidString: "6833C0F7-9A25-47E8-8FA7-1694A40312B3")!
    // The catalog lists this package and exports it as the template; the colors below need no file.
    static let packageURL = Bundle.main.url(forResource: "Original", withExtension: "xtheme", subdirectory: "Themes.bundle")
    static let palette = Palette(
        background: .system(.systemGroupedBackground), surface: .system(.secondarySystemGroupedBackground),
        primaryText: .system(.label), secondaryText: .system(.secondaryLabel),
        separator: .system(.separator), accent: .system(.systemBlue), onAccent: .system(.white)
    )
    // Symbolic UIKit colors adapt independently to each appearance and contrast setting.
    static let colors = Colors(light: palette, dark: palette,
                               lightIncreasedContrast: palette, darkIncreasedContrast: palette)
}
