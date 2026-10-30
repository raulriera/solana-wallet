import SwiftUI

/// A section of choices for the RPC provider in use.
struct ProviderSelectionSection: View {
    @Environment(\.palette) private var palette
    /// The provider in use, or `nil` before the choice is read.
    let selection: ProviderSettings.Provider?
    let customRPCs: [URL]
    /// The custom RPC waiting for the person to confirm its deletion.
    @Binding var removal: URL?
    let actions: any ProviderActions

    var body: some View {
        Section {
            ProviderRow(provider: .solana, isSelected: selection == .solana, actions: actions)
            ProviderRow(provider: .helius, isSelected: selection == .helius, actions: actions)
            ForEach(customRPCs, id: \.self) { url in
                CustomRPCRow(url: url, isSelected: selection == .custom(url), removal: $removal, actions: actions)
            }
            Button("Add Custom RPC…", systemImage: "plus", action: actions.addCustomRPC)
                .foregroundStyle(palette.accent)
        } header: {
            Text("RPC")
        } footer: {
            Text("Solana's public RPC is free and shared by everyone. It limits requests and isn't meant for heavy use.")
                .foregroundStyle(palette.secondaryText)
        }
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.separator)
    }
}
