/// Complete palettes for the system's appearance and contrast combinations.
public struct Colors: Sendable, Equatable {
    public let light: Palette
    public let dark: Palette
    public let lightIncreasedContrast: Palette
    public let darkIncreasedContrast: Palette

    /// Creates complete appearance defaults or resolved colors.
    /// - Parameters:
    ///   - light: Standard light appearance.
    ///   - dark: Standard dark appearance.
    ///   - lightIncreasedContrast: Light appearance with increased contrast.
    ///   - darkIncreasedContrast: Dark appearance with increased contrast.
    public init(light: Palette, dark: Palette, lightIncreasedContrast: Palette, darkIncreasedContrast: Palette) {
        self.light = light
        self.dark = dark
        self.lightIncreasedContrast = lightIncreasedContrast
        self.darkIncreasedContrast = darkIncreasedContrast
    }

    /// Resolves each appearance independently against the supplied overrides.
    /// - Parameter overrides: Validated appearance and role overrides.
    /// - Returns: Complete colors without cross-appearance fallback.
    func applying(_ overrides: [Appearance: [Role: Color]]) -> Colors {
        Colors(light: light.applying(overrides[.light] ?? [:]),
               dark: dark.applying(overrides[.dark] ?? [:]),
               lightIncreasedContrast: lightIncreasedContrast.applying(overrides[.lightIncreasedContrast] ?? [:]),
               darkIncreasedContrast: darkIncreasedContrast.applying(overrides[.darkIncreasedContrast] ?? [:]))
    }

    /// All appearance values for complete package serialization.
    var values: [Appearance: [Role: Color]] {
        [.light: light.values, .dark: dark.values,
         .lightIncreasedContrast: lightIncreasedContrast.values,
         .darkIncreasedContrast: darkIncreasedContrast.values]
    }
}

/// The manifest's supported appearance combinations.
enum Appearance: String, CaseIterable, Sendable {
    case light, dark, lightIncreasedContrast, darkIncreasedContrast
}
