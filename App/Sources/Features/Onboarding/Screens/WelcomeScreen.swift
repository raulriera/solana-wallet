import SwiftUI

/// Introduces wallet setup with buttons that create or import a wallet.
struct WelcomeScreen: View {
    @Environment(\.palette) private var palette
    let createWallet: () -> Void
    let importWallet: () -> Void

    var body: some View {
        ArrangementView {
            ScrollView {
                WelcomeIntroduction()
                    .padding(24)
                    .frame(maxWidth: LayoutMetrics.readableWidth)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        } secondary: {
            ScrollView {
                WelcomeActions(createWallet: createWallet, importWallet: importWallet)
                    .padding(24)
                    .frame(maxWidth: LayoutMetrics.readableWidth)
                    .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center, for: .alignment)
        }
        .arrangementViewStyle(.adaptive)
        .background(palette.background)
    }
}
