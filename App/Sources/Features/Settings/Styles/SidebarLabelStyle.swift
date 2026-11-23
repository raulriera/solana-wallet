import SwiftUI

/// A sidebar label style with a multicolor symbol.
///
/// On a primary-colored selection, the title and a monochrome symbol take the theme's color for content on the primary
/// color.
struct SidebarLabelStyle: LabelStyle {
    @Environment(\.backgroundProminence) private var backgroundProminence
    /// The color for a symbol without colors of its own, or `nil` for the primary style.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let isProminent = backgroundProminence == .increased
        Label {
            configuration.title
        } icon: {
            configuration.icon
                .foregroundStyle(.selectionAware(tint ?? .primary))
        }
        .labelStyle(.titleAndIcon)
        .symbolRenderingMode(isProminent ? .monochrome : .multicolor)
        .foregroundStyle(.selectionAware(.primary))
    }
}

extension LabelStyle where Self == SidebarLabelStyle {
    /// A title and a multicolor symbol that turns monochrome on a primary-colored selection.
    static var sidebar: Self { Self() }

    /// Returns a sidebar style that draws the symbol in one color.
    ///
    /// - Parameter tint: The symbol's color.
    /// - Returns: The label style.
    static func sidebar(tint: Color) -> Self { Self(tint: tint) }
}
