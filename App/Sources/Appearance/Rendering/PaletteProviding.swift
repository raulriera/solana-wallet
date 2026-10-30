import Observation
import SwiftUI

/// An observable source of a window's theme colors.
@MainActor protocol PaletteProviding: AnyObject, Observable {
    /// Returns the colors for an appearance and contrast.
    ///
    /// - Parameters:
    ///   - scheme: The light or dark appearance.
    ///   - contrast: The requested contrast.
    /// - Returns: The colors for that appearance and contrast.
    func palette(scheme: ColorScheme, contrast: ColorSchemeContrast) -> RenderedPalette
}
