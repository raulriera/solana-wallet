import SwiftUI

/// Presents an onboarding introduction inside the card surface owned by its screen.
struct TitleCardContent: View {
    @Environment(\.palette) private var palette
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
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
