import SwiftUI

/// A section of choices for the RPC provider in use.
struct RPCSelectionSection: View {
    /// The provider in use, or `nil` before the choice is read.
    let selection: RPCSettings.Provider?
    let customRPCs: [URL]
    let actions: any RPCActions

    var body: some View {
        Section {
            RPCRow(provider: .solana, isSelected: selection == .solana, actions: actions)
            RPCRow(provider: .helius, isSelected: selection == .helius, actions: actions)
            ForEach(customRPCs, id: \.self) { url in
                RPCRow(provider: .custom(url), isSelected: selection == .custom(url), actions: actions)
            }
            Button("Add Custom RPC…", systemImage: "plus", action: actions.addCustomRPC)
                .lineLimit(1)
        } header: {
            Text("RPC Provider")
        } footer: {
            Text("Solana's public RPC is free and shared by everyone. It limits requests and isn't meant for heavy use.")
        }
    }
}
