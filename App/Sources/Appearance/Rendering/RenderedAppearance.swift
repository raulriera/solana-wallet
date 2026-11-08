import Observation
import SwiftUI
import Themes

/// A theme's colors as SwiftUI colors.
struct RenderedPalette: Equatable {
    private let palette: Palette

    var background: SwiftUI.Color { self[.background] }
    var surface: SwiftUI.Color { self[.surface] }
    var text: SwiftUI.Color { self[.text] }
    var secondaryText: SwiftUI.Color { self[.secondaryText] }
    var separator: SwiftUI.Color { self[.separator] }
    var primary: SwiftUI.Color { self[.primary] }
    var onPrimary: SwiftUI.Color { self[.onPrimary] }
    var secondary: SwiftUI.Color { self[.secondary] }
    var onSecondary: SwiftUI.Color { self[.onSecondary] }
    var destructive: SwiftUI.Color { self[.destructive] }
    var onDestructive: SwiftUI.Color { self[.onDestructive] }
    var border: SwiftUI.Color { self[.border] }

    /// Creates SwiftUI colors from a theme palette.
    ///
    /// - Parameter palette: The theme palette.
    init(_ palette: Palette) {
        self.palette = palette
    }

    /// The SwiftUI color for a role.
    subscript(role: Palette.Role) -> SwiftUI.Color {
        SwiftUI.Color(palette[role])
    }
}

private extension SwiftUI.Color {
    /// Creates a SwiftUI color from a theme color.
    ///
    /// - Parameter color: The theme color.
    init(_ color: Themes.Color) {
        self = switch color {
        case .system(let name): SwiftUI.Color(uiColor: name.uiColor)
        case .srgb(let red, let green, let blue):
            SwiftUI.Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        }
    }
}

private extension Themes.Color.System {
    /// The UIKit semantic color for this system color name.
    var uiColor: UIColor {
        switch self {
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

/// A window's theme, ready to render.
@MainActor @Observable final class RenderedAppearance {
    private(set) var light = RenderedPalette(OriginalAppearance.tokens.colors.light)
    private(set) var dark = RenderedPalette(OriginalAppearance.tokens.colors.dark)
    private(set) var fontDesign = Font.Design(OriginalAppearance.tokens.fontDesign)

    /// Returns the colors for an appearance.
    ///
    /// - Parameter scheme: The light or dark appearance.
    /// - Returns: The colors for that appearance.
    func palette(scheme: ColorScheme) -> RenderedPalette {
        scheme == .dark ? dark : light
    }

    /// Loads a theme, falling back to the original appearance on failure.
    ///
    /// - Parameters:
    ///   - entry: The theme, or `nil` for the original appearance.
    ///   - catalog: The catalog that holds the theme.
    /// - Throws: A package read or cancellation error.
    func load(_ entry: ThemeEntry?, catalog: any ThemeCatalogProviding) async throws {
        do {
            let tokens: Tokens
            if let entry, entry.id != OriginalAppearance.id {
                tokens = OriginalAppearance.tokens.applying(try await catalog.pack(for: entry))
            } else {
                tokens = OriginalAppearance.tokens
            }
            try Task.checkCancellation()
            apply(tokens)
        } catch {
            if !Task.isCancelled {
                apply(OriginalAppearance.tokens)
            }
            throw error
        }
    }

    /// Sets the light and dark palettes and the font design from resolved tokens.
    ///
    /// - Parameter tokens: The resolved theme tokens.
    private func apply(_ tokens: Tokens) {
        light = RenderedPalette(tokens.colors.light)
        dark = RenderedPalette(tokens.colors.dark)
        fontDesign = Font.Design(tokens.fontDesign)
    }
}

private extension Font.Design {
    /// Creates a SwiftUI font design from a theme font design.
    ///
    /// - Parameter design: The theme font design.
    init(_ design: FontDesign) {
        self = switch design {
        case .default: .default
        case .rounded: .rounded
        case .serif: .serif
        case .monospaced: .monospaced
        }
    }
}
