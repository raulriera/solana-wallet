import SwiftUI

/// One of the window palette's color roles, so a component's style can name a theme color before it resolves.
nonisolated enum PaletteRole: Equatable, Sendable {
    case background
    case surface
    case primaryText
    case secondaryText
    case separator
    case accent
    case onAccent

    /// The role's color in a window's palette.
    /// - Parameter palette: The window's resolved palette.
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
