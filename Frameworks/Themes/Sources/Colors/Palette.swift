/// The semantic colors for one appearance.
public struct Palette: Sendable, Equatable {
    public let background: Color
    public let surface: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let separator: Color
    public let accent: Color
    public let onAccent: Color

    /// Creates a palette.
    ///
    /// - Parameters:
    ///   - background: The main content background color.
    ///   - surface: The color of content layered on the background.
    ///   - primaryText: The primary text color.
    ///   - secondaryText: The supporting text color.
    ///   - separator: The color of content dividers.
    ///   - accent: The color of emphasized content.
    ///   - onAccent: The color of content over the accent color.
    public init(background: Color, surface: Color, primaryText: Color, secondaryText: Color,
                separator: Color, accent: Color, onAccent: Color) {
        self.background = background
        self.surface = surface
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.separator = separator
        self.accent = accent
        self.onAccent = onAccent
    }

    /// Returns the palette with overrides applied.
    ///
    /// - Parameter overrides: The validated colors to override, by role.
    /// - Returns: The palette, with its own colors for omitted roles.
    func applying(_ overrides: [Role: Color]) -> Palette {
        Palette(background: overrides[.background] ?? background,
                surface: overrides[.surface] ?? surface,
                primaryText: overrides[.primaryText] ?? primaryText,
                secondaryText: overrides[.secondaryText] ?? secondaryText,
                separator: overrides[.separator] ?? separator,
                accent: overrides[.accent] ?? accent,
                onAccent: overrides[.onAccent] ?? onAccent)
    }

    /// Every color, by role.
    var values: [Role: Color] {
        [.background: background, .surface: surface, .primaryText: primaryText,
         .secondaryText: secondaryText, .separator: separator, .accent: accent, .onAccent: onAccent]
    }
}

/// A semantic color role.
enum Role: String, CaseIterable, Sendable {
    case background, surface, primaryText, secondaryText, separator, accent, onAccent
}
