/// A logo's representative sRGB color.
nonisolated struct ArtworkColor: Equatable, Sendable {
    /// The red component, from 0 to 1.
    let red: Double
    /// The green component, from 0 to 1.
    let green: Double
    /// The blue component, from 0 to 1.
    let blue: Double
}

nonisolated extension ArtworkColor {
    /// The gray for a logo without a color.
    static let placeholder = ArtworkColor(red: 199 / 255, green: 199 / 255, blue: 204 / 255)
}
