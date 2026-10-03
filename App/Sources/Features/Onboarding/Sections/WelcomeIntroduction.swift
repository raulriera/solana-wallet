import SwiftUI

/// Groups the welcome copy for either layout supplied by the screen.
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
