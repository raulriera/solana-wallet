import SwiftUI

/// Gives a split view's sidebar column the app's shared width and the theme's sidebar colors.
private struct SidebarColumn: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let sidebar = palette.sidebar
        content
            .navigationSplitViewColumnWidth(min: 320, ideal: 360)
            .scrollContentBackground(sidebar == nil ? .automatic : .hidden)
            .background(sidebar ?? .clear)
            .foregroundStyle(
                sidebar == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(text(palette.text)),
                sidebar == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(text(palette.secondaryText))
            )
    }

    /// Returns a text style that changes to the theme's color for content on the primary color in a selected row.
    ///
    /// - Parameter color: The color of the text in a row that isn't selected.
    /// - Returns: The text style.
    private func text(_ color: Color) -> SelectionAwareStyle {
        SelectionAwareStyle(standard: color, prominent: palette.onPrimary)
    }
}

/// A color that changes on a prominent background, such as a selected sidebar row filled with the tint.
private struct SelectionAwareStyle: ShapeStyle {
    let standard: Color
    let prominent: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.backgroundProminence == .increased ? prominent : standard
    }
}

extension View {
    /// Gives the sidebar column that contains this view the app's shared width and the theme's sidebar colors.
    ///
    /// - Returns: The view as a sidebar column, with the system sidebar when the theme has no sidebar color.
    func sidebarColumn() -> some View {
        modifier(SidebarColumn())
    }
}
