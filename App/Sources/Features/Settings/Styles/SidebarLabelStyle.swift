import SwiftUI

/// Places a sidebar label's title beside its multicolor symbol and keeps the symbol legible on an accent selection.
struct SidebarLabelStyle: LabelStyle {
    @Environment(\.backgroundProminence) private var backgroundProminence

    /// Shows the title and symbol, turning the symbol monochrome while its row has an increased-prominence selection.
    /// - Parameter configuration: The label's title and symbol.
    /// - Returns: A native title-and-icon label.
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(backgroundProminence == .increased ? .monochrome : .multicolor)
    }
}

extension LabelStyle where Self == SidebarLabelStyle {
    /// A title and multicolor symbol that turns monochrome on an accent selection, for sidebar destinations.
    static var sidebar: Self { Self() }
}
