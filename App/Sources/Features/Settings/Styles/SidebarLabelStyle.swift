import SwiftUI

/// Places a sidebar label's title beside its multicolor symbol and keeps the symbol legible on an accent selection.
struct SidebarLabelStyle: LabelStyle {
    @Environment(\.backgroundProminence) private var backgroundProminence
    /// The color for a symbol without colors of its own, which multicolor rendering would draw in the text color.
    var tint: Color?

    /// Shows the title and symbol, turning the symbol monochrome while its row has an increased-prominence selection.
    /// - Parameter configuration: The label's title and symbol.
    /// - Returns: A native title-and-icon label.
    func makeBody(configuration: Configuration) -> some View {
        let isProminent = backgroundProminence == .increased
        // A tinted symbol takes the selection's color while selected, as the multicolor symbols do.
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
    /// A title and multicolor symbol that turns monochrome on an accent selection, for sidebar destinations.
    static var sidebar: Self { Self() }

    /// A title and a symbol in one color, for a symbol without colors of its own, that turns monochrome on an accent
    /// selection.
    /// - Parameter tint: The symbol's color.
    /// - Returns: The label style.
    static func sidebar(tint: Color) -> Self { Self(tint: tint) }
}
