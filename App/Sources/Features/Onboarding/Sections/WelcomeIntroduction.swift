import SwiftUI

/// The welcome title card.
struct WelcomeIntroduction: View {
    @Environment(\.palette) private var palette

    var body: some View {
        TitleCardContent(
            title: "Welcome",
            message: "Create a new wallet or import one using your recovery phrase.",
            systemImage: "wallet.bifold.fill"
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface, in: .rect(cornerRadius: 24))
    }
}
