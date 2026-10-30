/// The complete palettes for each appearance and contrast combination.
public struct Colors: Sendable, Equatable {
    public let light: Palette
    public let dark: Palette
    public let lightIncreasedContrast: Palette
    public let darkIncreasedContrast: Palette

    /// Creates colors from a palette for each appearance.
    ///
    /// - Parameters:
    ///   - light: The light palette.
    ///   - dark: The dark palette.
    ///   - lightIncreasedContrast: The light palette with increased contrast.
    ///   - darkIncreasedContrast: The dark palette with increased contrast.
    public init(light: Palette, dark: Palette, lightIncreasedContrast: Palette, darkIncreasedContrast: Palette) {
        self.light = light
        self.dark = dark
        self.lightIncreasedContrast = lightIncreasedContrast
        self.darkIncreasedContrast = darkIncreasedContrast
    }

    /// Returns the colors with overrides applied to each appearance.
    ///
    /// - Parameter overrides: The validated colors to override, by appearance and role.
    /// - Returns: The complete colors.
    func applying(_ overrides: [Appearance: [Role: Color]]) -> Colors {
        Colors(light: light.applying(overrides[.light] ?? [:]),
               dark: dark.applying(overrides[.dark] ?? [:]),
               lightIncreasedContrast: lightIncreasedContrast.applying(overrides[.lightIncreasedContrast] ?? [:]),
               darkIncreasedContrast: darkIncreasedContrast.applying(overrides[.darkIncreasedContrast] ?? [:]))
    }

    /// Every color, by appearance and role.
    var values: [Appearance: [Role: Color]] {
        [.light: light.values, .dark: dark.values,
         .lightIncreasedContrast: lightIncreasedContrast.values,
         .darkIncreasedContrast: darkIncreasedContrast.values]
    }
}

/// An appearance and contrast combination.
enum Appearance: String, CaseIterable, Sendable {
    case light, dark, lightIncreasedContrast, darkIncreasedContrast
}
