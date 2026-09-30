/// Complete semantic colors for one appearance.
public struct Palette: Sendable, Equatable {
    public let background: Color
    public let surface: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let separator: Color
    public let accent: Color
    public let onAccent: Color

    /// Creates a complete palette without implicit defaults.
    /// - Parameters:
    ///   - background: The main content background.
    ///   - surface: Content layered on the background.
    ///   - primaryText: Primary content text.
    ///   - secondaryText: Supporting content text.
    ///   - separator: Content dividers.
    ///   - accent: Emphasized content.
    ///   - onAccent: Content displayed over the accent color.
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

    /// Resolves supplied roles against this palette.
    /// - Parameter overrides: Validated overrides for individual roles.
    /// - Returns: A complete palette retaining defaults for omitted roles.
    func applying(_ overrides: [Role: Color]) -> Palette {
        Palette(background: overrides[.background] ?? background,
                surface: overrides[.surface] ?? surface,
                primaryText: overrides[.primaryText] ?? primaryText,
                secondaryText: overrides[.secondaryText] ?? secondaryText,
                separator: overrides[.separator] ?? separator,
                accent: overrides[.accent] ?? accent,
                onAccent: overrides[.onAccent] ?? onAccent)
    }

    /// All role values for complete package serialization.
    var values: [Role: Color] {
        [.background: background, .surface: surface, .primaryText: primaryText,
         .secondaryText: secondaryText, .separator: separator, .accent: accent, .onAccent: onAccent]
    }
}

/// The manifest's supported semantic roles.
enum Role: String, CaseIterable, Sendable {
    case background, surface, primaryText, secondaryText, separator, accent, onAccent
}
