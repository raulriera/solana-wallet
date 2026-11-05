import SwiftUI

/// A borderless button style that shows only a label's icon, in the theme's primary color.
struct MoreInfoButtonStyle: PrimitiveButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        Button(configuration)
            .labelStyle(.iconOnly)
            .foregroundStyle(palette.primary)
            .buttonStyle(.borderless)
    }
}

extension PrimitiveButtonStyle where Self == MoreInfoButtonStyle {
    /// A borderless style that shows only a label's icon, in the theme's primary color.
    static var moreInfo: Self { Self() }
}
