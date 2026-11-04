import SwiftUI

/// A grouped form style that draws a form in the theme's colors at a readable width.
struct ThemedFormStyle: FormStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        Form {
            configuration.content
                .listRowBackground(palette.surface)
                .listRowSeparatorTint(palette.separator)
        }
        .formStyle(.grouped)
        .foregroundStyle(palette.text, palette.secondaryText)
        .scrollContentBackground(.hidden)
        .readableContentWidth()
        .background(palette.background)
    }
}

extension FormStyle where Self == ThemedFormStyle {
    /// A grouped form style in the theme's colors at a readable width.
    static var themed: Self { Self() }
}
