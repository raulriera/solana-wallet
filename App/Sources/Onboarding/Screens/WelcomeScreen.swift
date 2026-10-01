import SwiftUI

/// Introduces wallet setup and forwards the user's choice to the owning window.
struct WelcomeScreen: View {
    @Environment(\.palette) private var palette
    let createWallet: () -> Void
    let importWallet: () -> Void

    var body: some View {
        ArrangementView {
            ScrollView {
                WelcomeIntroduction()
                    .padding(24)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        } secondary: {
            ScrollView {
                WelcomeActions(createWallet: createWallet, importWallet: importWallet)
                    .padding(24)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        }
        .arrangementViewStyle(WelcomeArrangementStyle())
        .background(palette.background)
    }
}

#Preview {
    WelcomeScreen(createWallet: {}, importWallet: {})
        .tint(RenderedPalette(OriginalAppearance.palette).accent)
}
