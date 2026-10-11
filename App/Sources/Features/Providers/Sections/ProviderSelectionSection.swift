import SwiftUI

/// Inline choices for the RPC provider that every window uses.
struct ProviderSelectionSection: View {
    @Environment(\.palette) private var palette
    /// The provider in use, or `nil` before the choice is read.
    let selection: ProviderSettings.Provider?
    let actions: any ProviderActions

    var body: some View {
        Section {
            ProviderRow(provider: .solana, isSelected: selection == .solana, actions: actions)
            ProviderRow(provider: .helius, isSelected: selection == .helius, actions: actions)
        } header: {
            Text("RPC")
        } footer: {
            Text("Solana's public RPC is free and shared by everyone. It limits requests and isn't meant for heavy use.")
                .foregroundStyle(palette.secondaryText)
        }
    }
}
