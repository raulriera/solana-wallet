import SwiftUI

/// A color role in a window's palette.
nonisolated enum PaletteRole: Equatable, Sendable {
    case background
    case surface
    case primaryText
    case secondaryText
    case separator
    case accent
    case onAccent

    /// Returns the role's color in a palette.
    ///
    /// - Parameter palette: The window's palette.
    /// - Returns: The palette's color for this role.
    @MainActor
    func color(in palette: RenderedPalette) -> Color {
        switch self {
        case .background: palette.background
        case .surface: palette.surface
        case .primaryText: palette.primaryText
        case .secondaryText: palette.secondaryText
        case .separator: palette.separator
        case .accent: palette.accent
        case .onAccent: palette.onAccent
        }
    }
}
