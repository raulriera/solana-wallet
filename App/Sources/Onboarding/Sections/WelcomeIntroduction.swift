import SwiftUI

/// Groups the welcome copy for either layout supplied by the screen.
struct WelcomeIntroduction: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Welcome")
                .font(.largeTitle.bold())
                .foregroundStyle(palette.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Create a new wallet or import one using your recovery phrase.")
                .font(.body)
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
