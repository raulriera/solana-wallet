import SwiftUI

/// Presents a screen's introduction inside the card surface owned by that screen.
struct TitleCardContent<Icon: View>: View {
    @Environment(\.palette) private var palette
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    /// The decorative icon above the title, which inherits a large accent symbol style.
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            icon
                .font(.largeTitle)
                .foregroundStyle(palette.accent)
                .padding(.bottom, 8)
                .accessibilityHidden(true)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(palette.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.body)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.vertical, 8)
    }
}

extension TitleCardContent where Icon == Image {
    /// Creates an introduction led by an SF Symbol.
    /// - Parameters:
    ///   - title: The screen's title.
    ///   - message: A short description under the title.
    ///   - systemImage: The name of the SF Symbol above the title.
    init(title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        self.init(title: title, message: message) { Image(systemName: systemImage) }
    }
}
