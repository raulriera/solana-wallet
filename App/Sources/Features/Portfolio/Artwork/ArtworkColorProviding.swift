import Foundation

/// Finds the representative colors of token logos.
nonisolated protocol ArtworkColorProviding: Sendable {
    /// Returns a logo's representative color.
    ///
    /// - Parameter url: The logo's file URL in the app bundle or its HTTPS URL.
    /// - Returns: The logo's representative color, or `nil` when the logo can't load or has no color.
    func color(for url: URL) async -> ArtworkColor?
}
