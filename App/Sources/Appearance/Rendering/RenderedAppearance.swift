import Observation
import SwiftUI
import Themes

/// SwiftUI-ready values, converted once when a theme revision is loaded.
struct RenderedPalette: Equatable {
    let background: SwiftUI.Color
    let surface: SwiftUI.Color
    let primaryText: SwiftUI.Color
    let secondaryText: SwiftUI.Color
    let separator: SwiftUI.Color
    let accent: SwiftUI.Color
    let onAccent: SwiftUI.Color

    /// Converts a resolved framework palette to SwiftUI colors.
    /// - Parameter palette: A resolved framework palette.
    init(_ palette: Palette) {
        background = Self.color(palette.background)
        surface = Self.color(palette.surface)
        primaryText = Self.color(palette.primaryText)
        secondaryText = Self.color(palette.secondaryText)
        separator = Self.color(palette.separator)
        accent = Self.color(palette.accent)
        onAccent = Self.color(palette.onAccent)
    }

    /// Preserves adaptive system colors and converts literal sRGB components exactly.
    /// - Parameter value: A validated color token.
    /// - Returns: A color interpreted by the consuming view's current traits.
    private static func color(_ value: Themes.Color) -> SwiftUI.Color {
        switch value {
        case .system(let name): SwiftUI.Color(uiColor: systemColor(name))
        case .srgb(let red, let green, let blue):
            SwiftUI.Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        }
    }

    /// Maps the framework's closed symbolic vocabulary to UIKit's adaptive values.
    /// - Parameter name: A validated system color name.
    /// - Returns: The corresponding UIKit semantic color.
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

/// A window's small rendered snapshot; importing unrelated packs doesn't invalidate it.
@MainActor @Observable final class RenderedAppearance: PaletteProviding {
    private(set) var light = RenderedPalette(OriginalAppearance.palette)
    private(set) var dark = RenderedPalette(OriginalAppearance.palette)
    private(set) var lightIncreasedContrast = RenderedPalette(OriginalAppearance.palette)
    private(set) var darkIncreasedContrast = RenderedPalette(OriginalAppearance.palette)

    /// Selects a prepared palette using the consuming window's environment.
    /// - Parameters:
    ///   - scheme: The window's light or dark appearance.
    ///   - contrast: The window's requested contrast.
    /// - Returns: Complete colors without resolution or I/O in the render path.
    func palette(scheme: ColorScheme, contrast: ColorSchemeContrast) -> RenderedPalette {
        switch (scheme, contrast) {
        case (.dark, .increased): darkIncreasedContrast
        case (.dark, _): dark
        case (_, .increased): lightIncreasedContrast
        default: light
        }
    }

    /// Loads one revision outside rendering and discards cancelled results.
    /// - Parameters:
    ///   - entry: The selected installed revision; `nil` means original appearance.
    ///   - catalog: Shared package access.
    ///   - packages: Pure resolution against the app's complete baseline.
    /// - Throws: A package read or cancellation error. Unreadable themes render the baseline.
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

    /// Publishes the four small palettes together after all loading has completed.
    /// - Parameter colors: Fully resolved framework values.
    private func apply(_ colors: Colors) {
        light = RenderedPalette(colors.light)
        dark = RenderedPalette(colors.dark)
        lightIncreasedContrast = RenderedPalette(colors.lightIncreasedContrast)
        darkIncreasedContrast = RenderedPalette(colors.darkIncreasedContrast)
    }
}
