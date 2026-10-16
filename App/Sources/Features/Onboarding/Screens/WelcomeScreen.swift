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
                    .contentMargins(for: .container, edges: .horizontal)
                    .padding(.vertical, 24)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        } secondary: {
            ScrollView {
                WelcomeActions(createWallet: createWallet, importWallet: importWallet)
                    .contentMargins(for: .container, edges: .horizontal)
                    .padding(.vertical, 24)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        }
        .arrangementViewStyle(.adaptive)
        .background(palette.background)
    }
}

#Preview {
    WelcomeScreen(createWallet: {}, importWallet: {})
        .tint(RenderedPalette(OriginalAppearance.palette).accent)
}
