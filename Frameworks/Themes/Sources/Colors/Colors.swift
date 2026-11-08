/// The complete palettes for each appearance.
public struct Colors: Sendable, Equatable {
    public let light: Palette
    public let dark: Palette

    /// Creates colors from a palette for each appearance.
    ///
    /// - Parameters:
    ///   - light: The light palette.
    ///   - dark: The dark palette.
    public init(light: Palette, dark: Palette) {
        self.light = light
        self.dark = dark
    }

    /// Returns the colors with overrides applied to each appearance.
    ///
    /// - Parameter overrides: The validated colors to override, by appearance and role.
    /// - Returns: The complete colors.
    func applying(_ overrides: [Appearance: [Palette.Role: Color]]) -> Colors {
        Colors(light: light.applying(overrides[.light] ?? [:]), dark: dark.applying(overrides[.dark] ?? [:]))
    }

    /// Every color, by appearance and role.
    var values: [Appearance: [Palette.Role: Color]] {
        [.light: light.values, .dark: dark.values]
    }
}

/// A light or dark appearance.
enum Appearance: String, CaseIterable, Sendable {
    case light, dark
}
