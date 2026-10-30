import SwiftUI

/// A sidebar label style with a multicolor symbol that turns monochrome on an accent selection.
struct SidebarLabelStyle: LabelStyle {
    @Environment(\.backgroundProminence) private var backgroundProminence
    /// The color for a symbol without colors of its own, or `nil` for the primary style.
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        let isProminent = backgroundProminence == .increased
        let color = isProminent ? nil : tint
        Label {
            configuration.title
        } icon: {
            configuration.icon
                .foregroundStyle(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
        }
        .labelStyle(.titleAndIcon)
        .symbolRenderingMode(isProminent ? .monochrome : .multicolor)
    }
}

extension LabelStyle where Self == SidebarLabelStyle {
    /// A title and a multicolor symbol that turns monochrome on an accent selection.
    static var sidebar: Self { Self() }

    /// Returns a sidebar style that draws the symbol in one color.
    ///
    /// - Parameter tint: The symbol's color.
    /// - Returns: The label style.
    static func sidebar(tint: Color) -> Self { Self(tint: tint) }
}
