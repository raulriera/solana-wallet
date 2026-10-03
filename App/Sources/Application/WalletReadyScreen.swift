import SwiftUI

/// Temporary destination for reviewing the handoff until the main wallet interface is defined.
struct WalletReadyScreen: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Text("Wallet ready")
            .font(.title.bold())
            .foregroundStyle(palette.primaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
    }
}

#Preview {
    WalletReadyScreen()
}
