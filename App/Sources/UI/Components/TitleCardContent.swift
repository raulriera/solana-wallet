import SwiftUI

/// A screen's introduction with an icon, a title, and a message.
struct TitleCardContent<Icon: View>: View {
    @Environment(\.palette) private var palette
    let title: LocalizedStringResource
    let message: LocalizedStringResource
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
    ///
    /// - Parameters:
    ///   - title: The screen's title.
    ///   - message: A short description under the title.
    ///   - systemImage: The name of the SF Symbol above the title.
    init(title: LocalizedStringResource, message: LocalizedStringResource, systemImage: String) {
        self.init(title: title, message: message) { Image(systemName: systemImage) }
    }
}
