/// The semantic colors for one appearance.
public struct Palette: Sendable, Equatable {
    public let background: Color
    public let surface: Color
    public let text: Color
    public let secondaryText: Color
    public let separator: Color
    public let primary: Color
    public let onPrimary: Color
    public let secondary: Color
    public let onSecondary: Color
    public let destructive: Color
    public let onDestructive: Color

    /// Creates a palette.
    ///
    /// - Parameters:
    ///   - background: The main content background color.
    ///   - surface: The color of content layered on the background.
    ///   - text: The main text color.
    ///   - secondaryText: The supporting text color.
    ///   - separator: The color of content dividers.
    ///   - primary: The fill of primary buttons, and the color of links and controls without a fill.
    ///   - onPrimary: The color of text and symbols on the primary color.
    ///   - secondary: The fill of secondary buttons.
    ///   - onSecondary: The color of text and symbols on the secondary color.
    ///   - destructive: The fill of destructive buttons, and the color of destructive text without a fill.
    ///   - onDestructive: The color of text and symbols on the destructive color.
    public init(background: Color, surface: Color, text: Color, secondaryText: Color, separator: Color,
                primary: Color, onPrimary: Color, secondary: Color, onSecondary: Color,
                destructive: Color, onDestructive: Color) {
        self.background = background
        self.surface = surface
        self.text = text
        self.secondaryText = secondaryText
        self.separator = separator
        self.primary = primary
        self.onPrimary = onPrimary
        self.secondary = secondary
        self.onSecondary = onSecondary
        self.destructive = destructive
        self.onDestructive = onDestructive
    }

    /// Returns the palette with overrides applied.
    ///
    /// - Parameter overrides: The validated colors to override, by role.
    /// - Returns: The palette, with its own colors for omitted roles.
    func applying(_ overrides: [Role: Color]) -> Palette {
        Palette(background: overrides[.background] ?? background,
                surface: overrides[.surface] ?? surface,
                text: overrides[.text] ?? text,
                secondaryText: overrides[.secondaryText] ?? secondaryText,
                separator: overrides[.separator] ?? separator,
                primary: overrides[.primary] ?? primary,
                onPrimary: overrides[.onPrimary] ?? onPrimary,
                secondary: overrides[.secondary] ?? secondary,
                onSecondary: overrides[.onSecondary] ?? onSecondary,
                destructive: overrides[.destructive] ?? destructive,
                onDestructive: overrides[.onDestructive] ?? onDestructive)
    }

    /// Every color, by role.
    var values: [Role: Color] {
        [.background: background, .surface: surface, .text: text,
         .secondaryText: secondaryText, .separator: separator, .primary: primary, .onPrimary: onPrimary,
         .secondary: secondary, .onSecondary: onSecondary, .destructive: destructive, .onDestructive: onDestructive]
    }
}

/// A semantic color role.
enum Role: String, CaseIterable, Sendable {
    case background, surface, text, secondaryText, separator, primary, onPrimary, secondary, onSecondary
    case destructive, onDestructive
}
