import Observation
import SwiftUI
import Themes

/// A theme's colors as SwiftUI colors.
struct RenderedPalette: Equatable {
    let background: SwiftUI.Color
    let surface: SwiftUI.Color
    let primaryText: SwiftUI.Color
    let secondaryText: SwiftUI.Color
    let separator: SwiftUI.Color
    let accent: SwiftUI.Color
    let onAccent: SwiftUI.Color

    /// Creates SwiftUI colors from a theme palette.
    ///
    /// - Parameter palette: The theme palette.
    init(_ palette: Palette) {
        background = Self.color(palette.background)
        surface = Self.color(palette.surface)
        primaryText = Self.color(palette.primaryText)
        secondaryText = Self.color(palette.secondaryText)
        separator = Self.color(palette.separator)
        accent = Self.color(palette.accent)
        onAccent = Self.color(palette.onAccent)
    }

    /// Converts a theme color to a SwiftUI color.
    ///
    /// - Parameter value: The theme color.
    /// - Returns: The SwiftUI color.
    private static func color(_ value: Themes.Color) -> SwiftUI.Color {
        switch value {
        case .system(let name): SwiftUI.Color(uiColor: systemColor(name))
        case .srgb(let red, let green, let blue):
            SwiftUI.Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        }
    }

    /// Returns the UIKit color for a system color name.
    ///
    /// - Parameter name: The system color name.
    /// - Returns: The UIKit semantic color.
    private static func systemColor(_ name: Themes.Color.System) -> UIColor {
        switch name {
        case .label: .label
        case .secondaryLabel: .secondaryLabel
        case .tertiaryLabel: .tertiaryLabel
        case .quaternaryLabel: .quaternaryLabel
        case .systemFill: .systemFill
        case .secondarySystemFill: .secondarySystemFill
        case .tertiarySystemFill: .tertiarySystemFill
        case .quaternarySystemFill: .quaternarySystemFill
        case .placeholderText: .placeholderText
        case .tintColor: .tintColor
        case .systemBackground: .systemBackground
        case .secondarySystemBackground: .secondarySystemBackground
        case .tertiarySystemBackground: .tertiarySystemBackground
        case .systemGroupedBackground: .systemGroupedBackground
        case .secondarySystemGroupedBackground: .secondarySystemGroupedBackground
        case .tertiarySystemGroupedBackground: .tertiarySystemGroupedBackground
        case .separator: .separator
        case .opaqueSeparator: .opaqueSeparator
        case .link: .link
        case .systemBlue: .systemBlue
        case .systemBrown: .systemBrown
        case .systemCyan: .systemCyan
        case .systemGreen: .systemGreen
        case .systemIndigo: .systemIndigo
        case .systemMint: .systemMint
        case .systemOrange: .systemOrange
        case .systemPink: .systemPink
        case .systemPurple: .systemPurple
        case .systemRed: .systemRed
        case .systemTeal: .systemTeal
        case .systemYellow: .systemYellow
        case .systemGray: .systemGray
        case .systemGray2: .systemGray2
        case .systemGray3: .systemGray3
        case .systemGray4: .systemGray4
        case .systemGray5: .systemGray5
        case .systemGray6: .systemGray6
        case .black: .black
        case .white: .white
        case .clear: .clear
        }
    }
}

/// A window's theme colors for each appearance and contrast.
@MainActor @Observable final class RenderedAppearance: PaletteProviding {
    private(set) var light = RenderedPalette(OriginalAppearance.palette)
    private(set) var dark = RenderedPalette(OriginalAppearance.palette)
    private(set) var lightIncreasedContrast = RenderedPalette(OriginalAppearance.palette)
    private(set) var darkIncreasedContrast = RenderedPalette(OriginalAppearance.palette)

    func palette(scheme: ColorScheme, contrast: ColorSchemeContrast) -> RenderedPalette {
        switch (scheme, contrast) {
        case (.dark, .increased): darkIncreasedContrast
        case (.dark, _): dark
        case (_, .increased): lightIncreasedContrast
        default: light
        }
    }

    /// Loads the colors of a theme, falling back to the original colors on failure.
    ///
    /// - Parameters:
    ///   - entry: The theme, or `nil` for the original appearance.
    ///   - catalog: The catalog that holds the theme.
    ///   - packages: The service that resolves the theme's colors.
    /// - Throws: A package read or cancellation error.
    func load(_ entry: ThemeEntry?, catalog: any ThemeCatalogProviding, packages: any PackServicing) async throws {
        do {
            let colors: Colors
            if let entry, entry.id != OriginalAppearance.id {
                colors = packages.resolve(try await catalog.pack(for: entry), defaults: OriginalAppearance.colors)
            } else {
                colors = OriginalAppearance.colors
            }
            try Task.checkCancellation()
            apply(colors)
        } catch {
            if !Task.isCancelled { apply(OriginalAppearance.colors) }
            throw error
        }
    }

    /// Sets the four palettes from resolved colors.
    ///
    /// - Parameter colors: The resolved theme colors.
    private func apply(_ colors: Colors) {
        light = RenderedPalette(colors.light)
        dark = RenderedPalette(colors.dark)
        lightIncreasedContrast = RenderedPalette(colors.lightIncreasedContrast)
        darkIncreasedContrast = RenderedPalette(colors.darkIncreasedContrast)
    }
}
