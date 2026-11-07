import SwiftUI

/// The message that asks the person to confirm a custom RPC's deletion.
struct CustomRPCDeletionMessage: View {
    let url: URL
    /// Whether the RPC is the provider in use.
    let isSelected: Bool

    var body: some View {
        let host = Text(RPCSettings.Provider.custom(url).name)
        isSelected
            ? Text("\(host) will be deleted from this device, and every window will switch to Solana's public RPC.",
                   comment: "The Delete RPC confirmation's message for the RPC in use. The variable is the RPC's host.")
            : Text("\(host) will be deleted from this device.",
                   comment: "The Delete RPC confirmation's message. The variable is the RPC's host.")
    }
}
