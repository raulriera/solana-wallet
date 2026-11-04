import SwiftUI

/// A color role in a window's palette.
nonisolated enum PaletteRole: Equatable, Sendable {
    case background
    case surface
    case text
    case secondaryText
    case separator
    case primary
    case onPrimary
    case secondary
    case onSecondary
    case destructive
    case onDestructive

    /// Returns the role's color in a palette.
    ///
    /// - Parameter palette: The window's palette.
    /// - Returns: The palette's color for this role.
    @MainActor
    func color(in palette: RenderedPalette) -> Color {
        switch self {
        case .background: palette.background
        case .surface: palette.surface
        case .text: palette.text
        case .secondaryText: palette.secondaryText
        case .separator: palette.separator
        case .primary: palette.primary
        case .onPrimary: palette.onPrimary
        case .secondary: palette.secondary
        case .onSecondary: palette.onSecondary
        case .destructive: palette.destructive
        case .onDestructive: palette.onDestructive
        }
    }
}
