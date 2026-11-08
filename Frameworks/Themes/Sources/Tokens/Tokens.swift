/// A theme's complete colors and font design.
public struct Tokens: Sendable, Equatable {
    public let colors: Colors
    public let fontDesign: FontDesign

    /// Creates tokens from complete colors and a font design.
    ///
    /// - Parameters:
    ///   - colors: The complete colors.
    ///   - fontDesign: The font design.
    public init(colors: Colors, fontDesign: FontDesign) {
        self.colors = colors
        self.fontDesign = fontDesign
    }

    /// Returns these tokens with a pack's values applied, keeping these values where the pack omits them.
    ///
    /// - Parameter pack: A validated pack.
    /// - Returns: The complete tokens.
    public func applying(_ pack: Pack) -> Tokens {
        let overrides = pack.manifest.tokens
        return Tokens(colors: colors.applying(overrides.colors), fontDesign: overrides.fontDesign ?? fontDesign)
    }
}

extension Tokens {
    /// The token values a theme sets, leaving the others to defaults.
    struct Overrides: Sendable, Equatable {
        /// The colors to override, by appearance and role.
        var colors: [Appearance: [Palette.Role: Color]] = [:]
        /// The font design, or `nil` to keep the default.
        var fontDesign: FontDesign?
    }

    /// Overrides that set every token to these values.
    var overrides: Overrides {
        Overrides(colors: colors.values, fontDesign: fontDesign)
    }
}
