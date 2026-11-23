import SwiftUI

/// A style that uses the theme's color for content on the primary color in a selected row, and another style elsewhere.
nonisolated struct SelectionAwareStyle<Standard: ShapeStyle>: ShapeStyle {
    /// The style outside a selected row.
    let standard: Standard

    /// Returns the theme's color for content on the primary color in a selected row, or the standard style elsewhere.
    ///
    /// - Parameter environment: The environment where the style is drawn.
    /// - Returns: The style for the row's selection state.
    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.backgroundProminence == .increased
            ? AnyShapeStyle(environment.palette.onPrimary) : AnyShapeStyle(standard)
    }
}

nonisolated extension ShapeStyle {
    /// Returns a style that uses the theme's color for content on the primary color in a selected row.
    ///
    /// - Parameter standard: The style outside a selected row.
    /// - Returns: The selection-aware style.
    static func selectionAware<Standard: ShapeStyle>(_ standard: Standard) -> Self
    where Self == SelectionAwareStyle<Standard> {
        Self(standard: standard)
    }
}
