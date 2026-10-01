import Observation
import SwiftUI

/// A window's observable, already-converted appearance colors.
@MainActor protocol PaletteProviding: AnyObject, Observable {
    /// Selects cached colors using the consuming view's environment.
    /// - Parameters:
    ///   - scheme: The view's light or dark appearance.
    ///   - contrast: The view's requested contrast.
    /// - Returns: Complete rendered colors without resolution or I/O.
    func palette(scheme: ColorScheme, contrast: ColorSchemeContrast) -> RenderedPalette
}
