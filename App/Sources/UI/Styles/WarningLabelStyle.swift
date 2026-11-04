import SwiftUI

/// A label style with a symbol and text in the theme's destructive color.
struct WarningLabelStyle: LabelStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        Label {
            configuration.title
                .foregroundStyle(palette.destructive)
        } icon: {
            configuration.icon
                .foregroundStyle(palette.destructive)
        }
    }
}

extension LabelStyle where Self == WarningLabelStyle {
    /// A label with a symbol and text in the theme's destructive color.
    static var warning: Self { Self() }
}
