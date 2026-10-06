/// A logo's representative sRGB color, before a card style tints it.
nonisolated struct ArtworkColor: Equatable, Sendable {
    /// The red component, from 0 to 1.
    let red: Double
    /// The green component, from 0 to 1.
    let green: Double
    /// The blue component, from 0 to 1.
    let blue: Double
}
