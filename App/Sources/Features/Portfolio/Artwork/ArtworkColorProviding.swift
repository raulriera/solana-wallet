import Foundation

/// Finds the representative colors of token logos for decorative card backgrounds.
nonisolated protocol ArtworkColorProviding: Sendable {
    /// Samples a logo bundled with the app or on the provider's CDN.
    /// - Parameter url: The app's bundled copy, or the logo's HTTPS location on the provider's CDN.
    /// - Returns: The logo's representative color, or `nil` when the logo can't load or has no color.
    func color(for url: URL) async -> ArtworkColor?
}
