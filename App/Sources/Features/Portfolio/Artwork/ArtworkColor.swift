/// A logo's representative sRGB color, before a card style tints it.
nonisolated struct ArtworkColor: Equatable, Sendable {
    /// The red component, from 0 to 1.
    let red: Double
    /// The green component, from 0 to 1.
    let green: Double
    /// The blue component, from 0 to 1.
    let blue: Double
}

nonisolated extension ArtworkColor {
    /// The system gray behind a token's letter placeholder, for cards whose logo has no color.
    static let placeholder = ArtworkColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
}
